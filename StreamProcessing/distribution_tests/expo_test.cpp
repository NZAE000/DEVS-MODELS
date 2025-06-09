#include<iostream>
#include<cmath>
#include<cstdlib>
#include "util/random.hpp"

[[nodiscard]] double expo_distr(double rd, double lambda) noexcept {   
        return -(1/lambda)*std::log(1-rd);
}

constexpr u_int32_t iters {30};

int main(int argc, char** argv)
{	
	std::random_device rd_;
	std::mt19937 gen_{rd_()};
	std::uniform_real_distribution<double> uni_distr_{0, 1};

	double rate { static_cast<double>( std::atof(argv[1]) ) };

	double avg {};
	for (u_int32_t i=0; i<iters; ++i)
	{      
        double val_f { Random_t::exponential(rate) };//expo_distr(uni_distr_(gen_), rate)  };
		int val_i    { static_cast<int>(std::round(val_f)) }; 
		std::cout<<"f: "<< val_f <<" i: "<< val_i<<"\n";
		avg += val_f;
	}
	avg /= iters;
	std::cout<<"avg: "<<avg<<"\n";

	return 0;
}
