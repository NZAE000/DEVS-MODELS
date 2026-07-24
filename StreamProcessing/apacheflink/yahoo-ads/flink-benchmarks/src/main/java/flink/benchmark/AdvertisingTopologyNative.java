/**
 * Copyright 2015, Yahoo Inc.
 * Licensed under the terms of the Apache License 2.0.
 * Please see LICENSE file in the project root for terms.
 */
package flink.benchmark;

import benchmark.common.Utils;
import benchmark.common.advertising.CampaignProcessorCommon;
import benchmark.common.advertising.RedisAdCampaignCache;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.FilterFunction;
import org.apache.flink.api.common.functions.FlatMapFunction;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.api.java.tuple.Tuple3;
import org.apache.flink.api.java.tuple.Tuple7;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.util.Collector;
import org.apache.flink.util.ParameterTool;

import org.json.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;

/**
 * Yahoo advertising benchmark migrated to Apache Flink 2.2.
 *
 * Run with:
 *
 * flink run \
 *   -c flink.benchmark.AdvertisingTopologyNative \
 *   target/flink-benchmarks-0.1.0.jar \
 *   --confPath ../conf/localConf.yaml
 */
public final class AdvertisingTopologyNative {

    private static final Logger LOG = LoggerFactory.getLogger(AdvertisingTopologyNative.class);

    private AdvertisingTopologyNative() {
        // Utility class.
    }

    // Ti get values from file configuration (localConf.yaml)
    private static int getInt(Map<String, Object> conf, String key, int defaultValue) {

        final Object value = conf.get(key);
        if (value == null) { return defaultValue; }

        final int result;
        if (value instanceof Number) { result = ((Number) value).intValue();        } 
        else                         { result = Integer.parseInt(value.toString()); }

        if (result <= 0) { throw new IllegalArgumentException(key + " must be greater than zero"); }

        return result;
    }

    public static void main(final String[] args) throws Exception {

        final ParameterTool commandLine = ParameterTool.fromArgs(args);
        final String        confPath    = commandLine.getRequired("confPath"); // localConf.yaml

        @SuppressWarnings("unchecked")
        final Map<String, Object> conf = (Map<String, Object>) Utils.findAndReadConfigFile(confPath, true);

        final int kafkaPartitions    = ((Number) conf.get("kafka.partitions")).intValue();
        final int hosts              = ((Number) conf.get("process.hosts")).intValue();
        final int cores              = ((Number) conf.get("process.cores")).intValue();
        final String topic           = getKafkaTopic(conf);
        final String kafkaBrokers    = getKafkaBrokers(conf);
        final String redisHost       = getRedisHost(conf);
        final int defaultParallelism = hosts * cores;

        // Get specific operator parallelism.
        final int sourceParallelism = getInt(conf, "parallelism.source", Math.min(defaultParallelism, kafkaPartitions));

        // Check.
        if (sourceParallelism > kafkaPartitions) {
            throw new IllegalArgumentException(
                    "parallelism.source (" + sourceParallelism
                    + ") cannot exceed kafka.partitions ("
                    + kafkaPartitions + ")");
        }

        final int deserializeParallelism   = getInt(conf, "parallelism.deserialize",        defaultParallelism);
        final int filterParallelism        = getInt(conf, "parallelism.filter",             defaultParallelism);
        final int projectParallelism       = getInt(conf, "parallelism.project",            defaultParallelism);
        final int redisJoinParallelism     = getInt(conf, "parallelism.redis-join",         defaultParallelism);
        final int campaignPrcssParallelism = getInt(conf, "parallelism.campaign-processor", defaultParallelism);

        LOG.info("Configuration: {}", conf);
        LOG.info("Kafka brokers: {}, topic: {}, Redis host: {}, parallelism: {}",
                kafkaBrokers,
                topic,
                redisHost,
                defaultParallelism);

        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setBufferTimeout(getLong(conf, "flink.buffer-timeout", 100L));

        if (conf.containsKey("flink.checkpoint-interval")) {
            env.enableCheckpointing(getLong(conf, "flink.checkpoint-interval", 1000L));
        }

        env.setParallelism(defaultParallelism);

        final KafkaSource<String> kafkaSource =
                KafkaSource.<String>builder()
                        .setBootstrapServers(kafkaBrokers)
                        .setTopics(topic)
                        .setGroupId("yahoo-ads")
                        .setStartingOffsets(OffsetsInitializer.earliest())
                        .setValueOnlyDeserializer(new SimpleStringSchema())
                        .build();

        final DataStream<String> messageStream =
            env.fromSource(kafkaSource, WatermarkStrategy.noWatermarks(), "Kafka Source").setParallelism(sourceParallelism);
        
        final DataStream<Tuple7<String,String,String,String,String,String,String>>
            deserialized = messageStream.rebalance().flatMap(new DeserializeBolt()).name("Deserialize").setParallelism(deserializeParallelism);

        final DataStream<Tuple7<String, String, String, String, String, String, String>>
            views = deserialized.filter(new EventFilterBolt()).name("Filter Views").setParallelism(filterParallelism);

        final DataStream<Tuple2<String, String>> 
            projected = views.map(new ProjectEvent()).name("Project Event").setParallelism(projectParallelism);

        final DataStream<Tuple3<String, String, String>> 
            campaigns = projected.flatMap(new RedisJoinBolt(redisHost)).name("Redis Campaign Join").setParallelism(redisJoinParallelism);

        campaigns.keyBy(value -> value.f0).flatMap(new CampaignProcessor(redisHost)).name("Campaign Processor").setParallelism(campaignPrcssParallelism);             
                
        env.execute("Yahoo-Ads");
                
        //messageStream
        //        .rebalance()
//
        //        // Parse each JSON event.
        //        .flatMap(new DeserializeBolt())
        //        .name("Deserialize")
//
        //        // Keep only ad-view events.
        //        .filter(new EventFilterBolt())
        //        .name("Filter Views")
//
        //        // Select ad_id and event_time explicitly.
        //        .map(new ProjectEvent())
        //        .name("Project Event")
//
        //        // Join ad_id with campaign information stored in Redis.
        //        .flatMap(new RedisJoinBolt(redisHost))
        //        .name("Redis Campaign Join")
//
        //        // Aggregate campaign views by campaign identifier.
        //        .keyBy(value -> value.f0)
        //        .flatMap(new CampaignProcessor(redisHost))
        //        .name("Campaign Processor");

        //env.execute("Yahoo-Ads");
    }

    public static final class DeserializeBolt implements FlatMapFunction<String, Tuple7<String, String, String, String, String, String, String>> {

        @Override
        public void flatMap(String input, Collector<Tuple7<String, String, String, String, String, String, String>> out) 
        {
            final JSONObject obj = new JSONObject(input);
            out.collect(Tuple7.of(
                            obj.getString("user_id"),
                            obj.getString("page_id"),
                            obj.getString("ad_id"),
                            obj.getString("ad_type"),
                            obj.getString("event_type"),
                            obj.getString("event_time"),
                            obj.getString("ip_address")));
        }
    }

    public static final class EventFilterBolt implements FilterFunction<Tuple7<String, String, String, String, String, String, String>> {

        @Override
        public boolean filter(Tuple7<String, String, String, String, String, String, String> tuple) {
            return "view".equals(tuple.f4);
        }
    }

    /**
     * Replaces the removed positional projection:
     *
     * project(2, 5)
     */
    public static final class ProjectEvent implements MapFunction<Tuple7<String, String, String, String, String, String, String>, Tuple2<String, String>> {

        @Override
        public Tuple2<String, String> map(Tuple7<String, String, String, String, String, String, String> tuple) {
            return Tuple2.of(tuple.f2, tuple.f5);
        }
    }

    public static final class RedisJoinBolt extends RichFlatMapFunction<Tuple2<String, String>, Tuple3<String, String, String>> {

        private final String redisHost;
        private transient RedisAdCampaignCache redisAdCampaignCache;

        public RedisJoinBolt(String redisHost) { this.redisHost = redisHost; }

        @Override
        public void open(OpenContext openContext) 
        {
            LOG.info("Opening Redis campaign cache connection to {}", redisHost);
            redisAdCampaignCache = new RedisAdCampaignCache(redisHost);
            redisAdCampaignCache.prepare();
        }

        @Override
        public void flatMap(Tuple2<String, String> input, Collector<Tuple3<String, String, String>> out) 
        {
            final String adId       = input.f0;
            final String campaignId = redisAdCampaignCache.execute(adId);

            if (campaignId == null) { return; }
            out.collect(Tuple3.of(campaignId, adId, input.f1));
        }
    }

    public static final class CampaignProcessor extends RichFlatMapFunction<Tuple3<String, String, String>, String> {

        private final String redisHost;
        private transient CampaignProcessorCommon campaignProcessorCommon;

        public CampaignProcessor(String redisHost) { this.redisHost = redisHost; }

        @Override
        public void open(OpenContext openContext) 
        {
            LOG.info("Opening Redis campaign processor connection to {}", redisHost);
            campaignProcessorCommon = new CampaignProcessorCommon(redisHost);
            campaignProcessorCommon.prepare();
        }

        @Override
        public void flatMap(Tuple3<String, String, String> tuple, Collector<String> out) 
        {
            final String campaignId = tuple.f0;
            final String eventTime = tuple.f2;
            campaignProcessorCommon.execute(campaignId, eventTime);
        }
    }

    private static long getLong(Map<String, Object> conf, String key, long defaultValue) 
    {
        final Object value = conf.get(key);

        if (value == null) { return defaultValue; }
        if (value instanceof Number) { return ((Number) value).longValue(); }

        return Long.parseLong(value.toString());
    }

    private static String getKafkaBrokers(Map<String, Object> conf) 
    {
        if (!conf.containsKey("kafka.brokers")) {
            throw new IllegalArgumentException("No Kafka brokers found");
        }

        if (!conf.containsKey("kafka.port")) {
            throw new IllegalArgumentException("No Kafka port found");
        }

        @SuppressWarnings("unchecked")
        final List<String> brokers = (List<String>) conf.get("kafka.brokers");

        return listOfStringToString(brokers, String.valueOf(conf.get("kafka.port")));
    }

    private static String getKafkaTopic(Map<String, Object> conf) 
    {
        if (!conf.containsKey("kafka.topic")) {
            throw new IllegalArgumentException("No Kafka topic found");
        }

        return String.valueOf(conf.get("kafka.topic"));
    }

    private static String getRedisHost(Map<String, Object> conf) 
    {
        if (!conf.containsKey("redis.host")) {
            throw new IllegalArgumentException("No Redis host found");
        }

        return String.valueOf(conf.get("redis.host"));
    }

    public static String listOfStringToString(List<String> list, String port) 
    {

        final StringBuilder value = new StringBuilder();

        for (int index = 0; index < list.size(); index++) {
            if (index > 0) {
                value.append(',');
            }

            value.append(list.get(index)).append(':').append(port);
        }
        return value.toString();
    }
}