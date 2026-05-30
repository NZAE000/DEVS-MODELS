#pragma once

#include <random>
#include <sstream>
#include <fstream>


namespace myrandom {

	struct RandomBase_t {

		virtual ~RandomBase_t()   = default;
		virtual double generate() = 0;
		private:	std::random_device rd{};
		protected:  std::mt19937 gen{rd()};
	};

	//////////////////////////////////////////////////////
	struct Constant_t : RandomBase_t {
	
		explicit Constant_t(double v) 
		: val_{v}{}

		double generate() override { return val_; }

	private:
		double val_{};
	};

	//////////////////////////////////////////////////////
	struct Uniform_t : RandomBase_t {
	
		explicit Uniform_t(double from, double to) 
		: uniDistr{from, to}{}

		double generate() override { return uniDistr(gen); }

	private:
		std::uniform_real_distribution<double> uniDistr;
	};

	//////////////////////////////////////////////////////
	struct Exponential_t : RandomBase_t {
	
		explicit Exponential_t(double rate) 
		: expoDistr{rate}{}

		double generate() override { return expoDistr(gen); }

	private:
		std::exponential_distribution<double> expoDistr;
	};

	//////////////////////////////////////////////////////
	struct Normal_t : RandomBase_t {

		explicit Normal_t(double mean, double std) 
		: normalDistr{mean, std}{}

		double generate() override { return normalDistr(gen); }

	private:
		std::normal_distribution<double> normalDistr;
	};

	//////////////////////////////////////////////////////
	struct Poisson_t : RandomBase_t {

		explicit Poisson_t(int mean) 
		: poissonDistr(mean){}

		double generate() override { return poissonDistr(gen); }

	private:
		std::poisson_distribution<int> poissonDistr;
	};

	//////////////////////////////////////////////////////
	struct LogNormal_t : RandomBase_t {

		explicit LogNormal_t(double mean, double std) 
		: logNormalDistr{mean, std}{}

		double generate() override { return logNormalDistr(gen); }

	private:
		std::lognormal_distribution<double> logNormalDistr;
	};

	//////////////////////////////////////////////////////
	struct Gamma_t : RandomBase_t {

		explicit Gamma_t(double shape, double scale) 
		: gammaDistr{shape, scale}{}

		double generate() override { return gammaDistr(gen); }

	private:
		std::gamma_distribution<double> gammaDistr;
	};

	//////////////////////////////////////////////////////
	struct Bernoulli_t : RandomBase_t {
		explicit Bernoulli_t(double p) 
		: bernoulli(p) {}

		double generate() override { return bernoulli(gen); }

	private:
		std::bernoulli_distribution bernoulli;
	};


} // namespace myrandom

struct Random_t {
	
	// Variable exponencial de parámetro L=1.0/rate
	//  * https://en.cppreference.com/w/cpp/numeric/random/exponential_distribution
	//  * https://en.wikipedia.org/wiki/Exponential_distribution

// Distributions
	static double exponential(double rate);
	static double normal(double mean, double std);
	static double poisson(int mean);

	static double uniform(double min, double max);
	static int    integer(int32_t min, int32_t max);
	static double logNormal(double mean, double std);
	static double gamma(double shape, double scale);
	static double rayleigh(double sd);

	static void test(uint32_t totalPoints, const std::string& pathFileOut, bool exitAtFinish = true);
private:
    inline static std::random_device rd{};
	inline static std::mt19937 gen{rd()};
	inline static std::exponential_distribution<double> expoDistr;
    inline static std::normal_distribution<double> 		normalDistr;
	inline static std::poisson_distribution<int> 		poissonDistr;
	inline static std::lognormal_distribution<double> 	logNormalDistr;
	inline static std::gamma_distribution<double> 		gammaDistr;

// Setters
    static void setExponential(double rate);
    static void setNormal(double mean, double std);
	static void setPoisson(int mean);
	static void setLogNormal(double mean, double std);
	static void setGamma(double shape, double scale);
};