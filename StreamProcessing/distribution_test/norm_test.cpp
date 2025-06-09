#include<iostream>
#include<cmath>
#include<cstdlib>
#include "util/random.hpp"


constexpr u_int32_t iters {30};

int main(int argc, char** argv)
{	

	double mean { static_cast<double>( std::atof(argv[1]) ) };
    double std  { static_cast<double>( std::atof(argv[2]) ) };

	double avg {};
	for (u_int32_t i=0; i<iters; ++i)
	{      
        double val_f { Random_t::normal(mean, std) };//expo_distr(uni_distr_(gen_), rate)  };
		int val_i    { static_cast<int>(std::round(val_f)) }; 
		std::cout<<"f: "<< val_f <<" i: "<< val_i<<"\n";
		avg += val_f;
	}
	avg /= iters;
	std::cout<<"avg: "<<avg<<"\n";

	return 0;
}
