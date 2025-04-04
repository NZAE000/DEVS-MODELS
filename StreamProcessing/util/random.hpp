#pragma once

#include <random>
#include <sstream>
#include <fstream>

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
	static double rayleigh(double sd);

	static void test(uint32_t totalPoints, const std::string& pathFileOut, bool exitAtFinish = true);
private:
    inline static std::random_device rd{};
	inline static std::mt19937 gen{rd()};
	inline static std::exponential_distribution<double> expoDistr;
    inline static std::normal_distribution<double> normalDistr;
	inline static std::poisson_distribution<int> poissonDistr;


// Setters
    static void setExponential(double rate);
    static void setNormal(double mean, double std);
	static void setPoisson(int mean);
};
