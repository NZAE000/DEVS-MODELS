#pragma once

#include <random>
#include <sstream>
#include <fstream>


namespace myrandom {

	template<typename T>
	struct RandomBase_t {

		virtual ~RandomBase_t() = default;
		virtual T generate() = 0;
		protected: 
			std::mt19937 gen{std::random_device{}()};
	};

	
	/****************************************************
		RandomBase_t<T>
		|
		├── Constant_t<T>
		├── Uniform_t<T>          (integral o floating)
		├── Exponential_t<T>      (floating)
		├── Normal_t<T>           (floating)
		├── Poisson_t<T>          (integral)
		├── Lognormal_t<T>        (floating)
		├── Gamma_t<T>            (floating)
		└── Bernoulli_t           (bool)
	****************************************************/

	//////////////////////////////////////////////////////
	template<typename TYPE>
	struct Constant_t : RandomBase_t<TYPE> {
	
		explicit Constant_t(TYPE v) 
		: val_{v}{}

		TYPE generate() override { return val_; }

	private:
		TYPE val_{};
	};

	//////////////////////////////////////////////////////
	template<typename TYPE>
	requires std::integral<TYPE> || std::floating_point<TYPE>
	struct Uniform_t : RandomBase_t<TYPE> {
	
		explicit Uniform_t(TYPE from, TYPE to) 
		: uniform{from, to}{}

		TYPE generate() override { return uniform(this->gen); }

	private:
		using UniformDistribution =
			std::conditional_t<
				std::is_integral_v<TYPE>,
				std::uniform_int_distribution<TYPE>,
				std::uniform_real_distribution<TYPE>>;

		UniformDistribution uniform;
	};

	//////////////////////////////////////////////////////
	template<std::floating_point TYPE>
	struct Exponential_t : RandomBase_t<TYPE> {
	
		explicit Exponential_t(TYPE rate) 
		: exponential{rate}{}

		TYPE generate() override { return exponential(this->gen); }

	private:
		std::exponential_distribution<TYPE> exponential;
	};

	//////////////////////////////////////////////////////
	template<std::floating_point TYPE>
	struct Normal_t : RandomBase_t<TYPE> {

		explicit Normal_t(TYPE mean, TYPE std) 
		: normal{mean, std}{}

		TYPE generate() override { return normal(this->gen); }

	private:
		std::normal_distribution<TYPE> normal;
	};

	//////////////////////////////////////////////////////
	template<std::integral TYPE>
	struct Poisson_t : RandomBase_t<TYPE> {

		explicit Poisson_t(double mean) 
		: poisson(mean){}

		TYPE generate() override { return poisson(this->gen); }

	private:
		std::poisson_distribution<TYPE> poisson;
	};

	//////////////////////////////////////////////////////
	template<std::floating_point TYPE>
	struct Lognormal_t : RandomBase_t<TYPE> {

		explicit Lognormal_t(TYPE mean, TYPE std) 
		: lognormal{mean, std}{}

		TYPE generate() override { return lognormal(this->gen); }

	private:
		std::lognormal_distribution<TYPE> lognormal;
	};

	//////////////////////////////////////////////////////
	template<std::floating_point TYPE>
	struct Gamma_t : RandomBase_t<TYPE> {

		explicit Gamma_t(TYPE shape, TYPE scale) 
		: gamma{shape, scale}{}

		TYPE generate() override { return gamma(this->gen); }

	private:
		std::gamma_distribution<TYPE> gamma;
	};

	//////////////////////////////////////////////////////
	struct Bernoulli_t : RandomBase_t<bool> {
		explicit Bernoulli_t(double p) 
		: bernoulli(p) {}

		bool generate() override { return bernoulli(this->gen); }

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