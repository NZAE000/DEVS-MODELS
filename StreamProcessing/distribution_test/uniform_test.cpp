#include<iostream>
#include "util/random.hpp"


constexpr u_int32_t iters {30};

int main(int argc, char** argv)
{
    double min  { static_cast<double>( std::atof(argv[1]) ) };
    double max  { static_cast<double>( std::atof(argv[2]) ) };


    double avg {};
	for (u_int32_t i=0; i<iters; ++i)
	{      
        double val_f { Random_t::uniform(min, max) };
		int val_i    { static_cast<int>(std::round(val_f)) }; 
		std::cout<<"f: "<< val_f <<" i: "<< val_i<<"\n";
		avg += val_f;
	}
	avg /= iters;
	std::cout<<"avg: "<<avg<<"\n";

    return 0;
}