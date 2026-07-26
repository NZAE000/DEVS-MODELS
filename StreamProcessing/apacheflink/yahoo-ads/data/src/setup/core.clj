;; Copyright 2015, Yahoo Inc.
;; Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.

(ns setup.core
  (:import java.util.UUID)
  (:import java.io.FileNotFoundException)
  (:require [clj-kafka.new.producer :refer :all]
            [redis.core :as redis]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clj-json.core :as json]
            [clojure.tools.cli :as cli]
            [clj-yaml.core :as yaml])
  (:gen-class)
  (:refer-clojure :exclude [send]))

(def num-campaigns 100)
(def view-capacity-per-window 10)
(def kafka-event-count  (* 10 1000000)) ; N millions
(def time-divisor 10000)               ; 10 seconds

(defn make-ids [n]
  (for [n (range n)]
    (.toString (java.util.UUID/randomUUID))))

(defn write-ids [campaigns ads]
  (println "Writing ids to files.")
  ;; Write the ids out to files
  (with-open [campaign-o (clojure.java.io/writer "campaign-ids.txt")
              ads-o (clojure.java.io/writer "ad-ids.txt")]
    (binding [*out* campaign-o]
      (doseq [campaign campaigns]
        (println campaign)))
    (binding [*out* ads-o]
      (doseq [ad ads]
        (println ad)))))

(defn load-ids []
  (try
    (with-open [campaigns (clojure.java.io/reader "campaign-ids.txt")
                ads (clojure.java.io/reader "ad-ids.txt")]
      (println "Loading Ids.")
      {:campaigns (doall (line-seq campaigns))
       :ads (doall (line-seq ads))}
      (println "loading done"))
    (catch FileNotFoundException e
      (println "Failed to load ids from file."))))

(defn write-to-redis [campaigns ads redis-host]
  ;; Hook up the redis DB
  (println "Writing initial data to Redis.")
  (with-open [ad-to-campaign-o (clojure.java.io/writer "ad-to-campaign-ids.txt")]
    (binding [*out* ad-to-campaign-o]
      (let [campaigns-ads (map vector campaigns (partition 10 ads))]
        (redis/with-server {:host redis-host}
          (redis/flushall)
          (doseq [[campaign campaign-ads] campaigns-ads]
            (redis/sadd "campaigns" campaign)
            (doseq [ad campaign-ads]
              (println (str "{ \""ad "\": \"" campaign "\"}"))
              (redis/set ad campaign))))))))

(defn write-to-kafka [ads kafka-hosts]
  ;; Put some crap in Kafka
  (println "Setting up kafka topic.")
  (with-open [p (producer {"bootstrap.servers" kafka-hosts}
                          (byte-array-serializer)
                          (byte-array-serializer))]
    (println "Creating kafka senders.")
    (let [ad-types ["banner", "modal", "sponsored-search", "mail", "mobile"]
          event-types ["view", "click", "purchase"]
          start-time (System/currentTimeMillis)
          skew 0 ;(- (rand-int 1000))
          late-by (- (if nil ;(= 0 (rand-int 1000))
                       (rand-int 50000)
                       0))]
;          kafka-senders
      (with-open [kafka-o (clojure.java.io/writer "kafka-json.txt")]
        (doseq [v (partition 100000 (map vector
                                         (range kafka-event-count)
                                         (make-ids kafka-event-count)
                                         (make-ids kafka-event-count)))]
          (reduce
           (fn [acc sender]
             (if (= (mod acc 10000) 0)
               (println acc))
             @sender
             (+ 1 acc))
           0
           (doall
            (for [[n user_id page_id] v]
              (let [json-str (str "{\"user_id\": \"" user_id
                                  "\", \"page_id\": \"" page_id
                                  "\", \"ad_id\": \"" (rand-nth ads)
                                  "\", \"ad_type\": \"" (rand-nth ad-types)
                                  "\", \"event_type\": \"" (rand-nth event-types)
                                  "\", \"event_time\": \"" (str (+ start-time (* n 10) skew late-by))
                                  "\", \"ip_address\": \"1.2.3.4\"}")]
                (.write kafka-o (str json-str "\n"))
                (send p (record "ad-events" (.getBytes json-str))))))))))))

;; Returns a map campaign-id->(timestamp->count)
(defn dostats []
  (println "Getting Stats!")
  (let [json-string-mapper (map json/parse-string)
        ad->campaign (with-open [ad-campaign (io/reader "ad-to-campaign-ids.txt")]
                       (doall
                        (reduce merge (map json/parse-string (line-seq ad-campaign)))))
        campaign-buckets-mapper (map (fn camp-buck-map [event]
                                       (let [event-time (Long. (get event "event_time"))
                                             time-bucket (long (/ event-time time-divisor))
                                             ad-id (get event "ad_id")
                                             type (get event "event_type")
                                             campaign-id (get ad->campaign ad-id)]
                                         [campaign-id time-bucket type])))]
    (with-open [kafkas (io/reader "kafka-json.txt")]
      (transduce (comp json-string-mapper campaign-buckets-mapper)
                 (fn transduc
                   ([one] one)
                   ([acc [campaign-id time-bucket type]]
                    (let [current-campaign-map (get acc campaign-id)
                          current-timebucket-val (or (get current-campaign-map time-bucket) 0)
                          next-timebucket-val (+ current-timebucket-val 1)]
                      (if (= type "view")
                        (assoc acc campaign-id
                               (assoc current-campaign-map time-bucket
                                      next-timebucket-val))
                        acc))))
                 {}
                 (line-seq kafkas)))))

(defn get-stats [redis-host]
  (with-open [seen-file (clojure.java.io/writer "seen.txt")
              updated-file (clojure.java.io/writer "updated.txt")]
    (letfn [(data-printer [[seen updated]]
              (.write seen-file (str seen "\n"))
              (.write updated-file (str updated "\n")))]
      (redis/with-server {:host redis-host}
        (doall
         (map data-printer
              (apply concat
                     (let [campaigns (redis/smembers "campaigns")]
                       (for [campaign campaigns]
                         (let [windows-key (redis/hget campaign "windows")
                               window-count (redis/llen windows-key)
                               windows (redis/lrange windows-key 0 window-count)]
                           (for [window-time windows]
                             (let [window-key (redis/hget campaign window-time)
                                   seen (redis/hget window-key "seen_count")
                                   time_updated (redis/hget window-key "time_updated")]
                               [seen (- (Long/parseLong time_updated) (Long/parseLong window-time))]))))))))))))

(defn gen-ads [redis-host]
  (redis/with-server {:host redis-host}
    (let [campaigns (redis/smembers "campaigns")
          ads (into [] (make-ids (* num-campaigns 10)))
          campaigns-ads (map vector campaigns (partition 10 ads))]
      (if (< (count campaigns) num-campaigns)
        (throw (RuntimeException. "No Campaigns found. Please run with -n first.")))
      (doseq [[campaign campaign-ads] campaigns-ads]
        (doseq [ad campaign-ads]
          (redis/set ad campaign)))
      ads)))

(defn make-kafka-event-at [time with-skew? ads user-ids page-ids]
  (let [ad-types ["banner", "modal", "sponsored-search", "mail", "mobile"]
        event-types ["view", "click", "purchase"]
        skew (if with-skew?
               (- 50 (rand-int 100))
               0)
        late-by (if with-skew?
                  (- (if (= 0 (rand-int 100000))
                       (rand-int 60000)
                       0))
                  0)
        time (+ time skew late-by)]
    (str "{\"user_id\": \"" (rand-nth user-ids)
         "\", \"page_id\": \"" (rand-nth page-ids)
         "\", \"ad_id\": \"" (rand-nth ads)
         "\", \"ad_type\": \"" (rand-nth ad-types)
         "\", \"event_type\": \"" (rand-nth event-types)
         "\", \"event_time\": \"" (str time)
         "\", \"ip_address\": \"1.2.3.4\"}")))
  
(defn parse-positive-long [text field line-number]
  (try
    (let [value (Long/parseLong text)]
      (when (<= value 0)
        (throw
          (IllegalArgumentException.
            (str field
                 " must be greater than zero at line "
                 line-number))))
      value)

    (catch NumberFormatException _
      (throw
        (IllegalArgumentException.
          (str "Invalid "
               field
               " at line "
               line-number
               ": "
               text))))))
  
(defn parse-workload-line [line-number line]
  ;; Remove inline comments and surrounding whitespace.
  (let [content (-> line
                    (str/split #"#" 2)
                    first
                    str/trim)]

    (when-not (str/blank? content)
      (let [fields (str/split content #"\s+")]

        (when-not (= 2 (count fields))
          (throw
            (IllegalArgumentException.
              (str "Expected '<requests> <rate>' at line "
                   line-number
                   ": "
                   line))))

        {:requests
         (parse-positive-long
           (first fields)
           "requests"
           line-number)

         :rate
         (parse-positive-long
           (second fields)
           "rate"
           line-number)}))))
  
(defn read-workloads [workloads-path]
  (let [workloads
        (->> (slurp workloads-path)
             str/split-lines
             (keep-indexed
               (fn [index line]
                 (parse-workload-line
                   (inc index)
                   line)))
             vec)]

    (when (empty? workloads)
      (throw
        (IllegalArgumentException.
          (str "No workloads found in "
               workloads-path))))

    workloads))

(defn sleep-until! [target-ns]
  (loop []
    (let [remaining-ns
          (- target-ns (System/nanoTime))]

      (when (pos? remaining-ns)
        (let [millis (quot remaining-ns 1000000)
              nanos  (int (rem remaining-ns 1000000))]

          (Thread/sleep millis nanos)
          (recur))))))

(defn emit-workload!
  [p stage-number requests rate with-skew? kafka-topic ads user-ids page-ids stage-log]

  (println
    "Starting workload"
    stage-number
    "- requests:"
    requests
    "rate:"
    rate
    "events/s")

  (let [start-ns   (System/nanoTime)
        start-ms   (System/currentTimeMillis)
        period-ns  (/ 1000000000.0 rate)]

    (doseq [index (range requests)]
      (let [target-ns
            (+ start-ns
               (long (* index period-ns)))]

        (sleep-until! target-ns)

        (let [event-time
              (+ start-ms
                 (long
                   (/ (* index 1000.0)
                      rate)))]

          (send
            p
            (record
              kafka-topic
              (.getBytes
                (make-kafka-event-at
                  event-time
                  with-skew?
                  ads
                  user-ids
                  page-ids)))))))

    (let [end-ns       (System/nanoTime)
          end-ms       (System/currentTimeMillis)
          elapsed-sec  (/ (double (- end-ns start-ns))
                          1000000000.0)
          actual-rate  (/ requests elapsed-sec)]

      (.write
        stage-log
        (format
          "%d\t%d\t%d\t%d\t%d\t%.3f\t%.3f%n"
          stage-number
          requests
          rate
          start-ms
          end-ms
          elapsed-sec
          actual-rate))

      (.flush stage-log)

      (println
        "Completed workload"
        stage-number
        "- elapsed:"
        elapsed-sec
        "seconds; achieved rate:"
        actual-rate
        "events/s"))))

(defn run-dynamic [workloads-path with-skew? kafka-hosts kafka-topic redis-host]
  (let [workloads (read-workloads workloads-path)
        ads       (gen-ads redis-host)
        page-ids  (vec (make-ids 100))
        user-ids  (vec (make-ids 100))]

    (println
      "Starting dynamic load with"
      (count workloads)
      "workload(s) from"
      workloads-path)

    (with-open
      [p
       (producer
         {"bootstrap.servers" kafka-hosts}
         (byte-array-serializer)
         (byte-array-serializer))

       stage-log
       (io/writer "dynamic-load-stages.tsv")]

      (.write
        stage-log
        (str
          "stage\trequests\tconfigured_rate\t"
          "start_ms\tend_ms\telapsed_seconds\t"
          "achieved_rate\n"))

      (doseq [[index workload]
              (map-indexed vector workloads)]

        (emit-workload!
          p
          (inc index)
          (:requests workload)
          (:rate workload)
          with-skew?
          kafka-topic
          ads
          user-ids
          page-ids
          stage-log))

      ;; Ensure all buffered producer records have been delivered
      ;; before the process finishes.
      ;;(.flush p)
      )

    (println
      "Dynamic load completed:"
      (count workloads)
      "workload(s).")))

(defn run [throughput with-skew? kafka-hosts redis-host]
  (println "Running, emitting" throughput "tuples per second.")
  (let [ads (gen-ads redis-host)
        page-ids (make-ids 100)
        user-ids (make-ids 100)
        start-time-ns (* 1000000 (System/currentTimeMillis))
        period-ns (long (/ 1000000000 throughput))
        times (map #(+ (* period-ns %) start-time-ns) (range))]
    (with-open [p (producer {"bootstrap.servers" kafka-hosts}
                            (byte-array-serializer)
                            (byte-array-serializer))]
      (doseq [t times]
        (let [cur (System/currentTimeMillis)
              t (long (/ t 1000000))]
          (if (> t cur)
            (Thread/sleep (- t cur))
            (future
              (if (> cur (+ t 100))
                (println "Falling behind by:" (- cur t) "ms"))))
          (send p (record "ad-events"
                          (.getBytes (make-kafka-event-at t with-skew? ads user-ids page-ids)))))))))

(defn do-new-setup [redis-host]
  ;; Hook up the redis DB
  (println "Writing campaigns data to Redis.")
  (let [campaigns (make-ids num-campaigns)]
    (redis/with-server {:host redis-host}
      (redis/flushall)
      (doseq [campaign campaigns]
        (redis/sadd "campaigns" campaign)))))

(defn check-correct [redis-host]
  (let [stats (doall (dostats))]
    (println "Got stats!")
    (println "Checking Redis!")
    (redis/with-server {:host redis-host}
      (doseq [[campaign c-stats] stats]
        (doseq [[timestamp val] c-stats]
          (let [timestamp-key (redis/hget campaign (str (* timestamp time-divisor)))]
            (if timestamp-key
              (let [seen-count (Long. (redis/hget timestamp-key "seen_count"))]
                (if (not= seen-count val)  ;when
                  (println (str
                            "Campaign: " (pr-str campaign)
                            " has an entry for Timestamp: " (pr-str timestamp)
                            " DIFFER in seen count: (" (pr-str seen-count) ", " (pr-str val) ")"))
                  (println (str
                             "Campaign: " (pr-str campaign)
                             " has an entry for Timestamp: " (pr-str timestamp)
                             " CORRECT in seen count: (" (pr-str seen-count) ", " (pr-str val) ")"))
                  ))
              (println (str
                        "Campaign: " (pr-str campaign)
                        " has no entry for Timestamp: " (str timestamp ) " , was expecting " (pr-str val))))))))))

(defn do-setup [conf]
  (let [{campaigns :campaigns ads :ads} (load-ids)]
    (if (or (nil? campaigns) (nil? ads))
      ;; Create new ids
      (let [campaigns (make-ids num-campaigns)
            ads (into [] (make-ids (* num-campaigns 10)))]
        (write-to-redis campaigns ads (conf :redis-host))
        (write-to-kafka ads (conf :kakfa-brokers))
        (write-ids campaigns ads))
      (write-to-redis campaigns ads))))

(defn get-conf [confPath]
  (let [conf         (yaml/parse-string (slurp confPath))
        redis-host   (get conf :redis.host)
        kafka-port   (get conf :kafka.port)
        kafka-topic  (get conf :kafka.topic)
        kafka-hosts
        (str/join
          ","
          (for [broker (get conf :kafka.brokers)]
            (str broker ":" kafka-port)))]

    (when (nil? kafka-topic)
      (throw
        (IllegalArgumentException.
          "Missing kafka.topic in configuration")))

    (println
      {:redis-host redis-host
       :kakfa-brokers kafka-hosts
       :kafka-topic kafka-topic})

    {:redis-host redis-host
     :kakfa-brokers kafka-hosts
     :kafka-topic kafka-topic}))

(def cli-options
  [["-s" "--setup" "Set up for catchup-simulation-mode (or re-setup if the .txt files exist)"]
   ["-c" "--check" "Check that the catchup-mode data has been properly processed by whatever is being benchmarked."]
   ["-n" "--new"   "Set up redis for a new real-time simulation. This must be run on only one node, only once before starting multiple kafka-feeders (-r) on multiple nodes."]
   ["-r" "--run"   "Run - emit events to kafka at a particular frequency This is used for the real-time simulation. Frequency specified with other options."]
   ["-t" "--throughput COUNT" "Should be used with '-r'. This is the number of tuples per second to emit. (Obviously it can't emit ridiculous numbers per second.)"
    :default 0
    :parse-fn #(Long/parseLong %)]
   ["-d" "--dynamic-workloads PATH" "Path to a file containing '<requests> <rate>' workloads."
    :parse-fn #(String/valueOf %)]
   ["-w" "--with-skew" "Add minor skew and late tuples into the mix."]
   ["-g" "--get-stats" "Read through redis and collect stats on end-to-end latency and so forth for the real-time simulation."]
   ["-a" "--configPath PATH" "Path to config yaml file"
    :default "./benchmarkConf.yaml"
    :parse-fn #(String/valueOf %)]])

(defn -main
  [& args]

  (let [{:keys [options arguments errors summary]}
        (cli/parse-opts args cli-options)

        conf         (get-conf (:configPath options))
        kafka-hosts  (get conf :kakfa-brokers)
        kafka-topic  (get conf :kafka-topic)
        redis-host   (get conf :redis-host)]

    (cond
      (and (:setup options) (:check options))
      (println "Specify either --setup OR --check")

      (:setup options)
      (do-setup conf)

      (:check options)
      (check-correct redis-host)

      (:new options)
      (do-new-setup redis-host)

      (and (:run options)
           (:dynamic-workloads options))
      (run-dynamic
        (:dynamic-workloads options)
        (:with-skew options)
        kafka-hosts
        kafka-topic
        redis-host)

      (:run options)
      (run
        (:throughput options)
        (:with-skew options)
        kafka-hosts
        redis-host)

      (:get-stats options)
      (get-stats redis-host)

      :else
      (println summary))))