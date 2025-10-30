#include "random.hpp"

double Random_t::exponential(double rate)
{
	//std::random_device rd;
	//std::mt19937 gen(rd());
	//std::exponential_distribution<double> expoDistr(1.0/rate);
    setExponential(rate);
	return( expoDistr(gen) );
}

double Random_t::normal(double mean, double std)
{
	//std::random_device rd;
	//std::mt19937 gen(rd());
	//std::normal_distribution<double> normalDistr(mean,std);
	setNormal(mean, std);
	double x {};
	while ((x = normalDistr(gen)) < 0){}
	return(x);
}

double Random_t::poisson(int mean)
{
	setPoisson(mean);
	return( poissonDistr(gen) );
}	

void Random_t::setNormal(double mean, double std) {
    normalDistr = std::normal_distribution<double>(mean, std);
}
void Random_t::setExponential(double rate) {
    expoDistr = std::exponential_distribution<double>(rate);
}
void Random_t::setPoisson(int mean){
	poissonDistr = std::poisson_distribution<>(mean);
}


double Random_t::uniform(double min, double max)
{
	std::random_device rd;
	std::mt19937 gen(rd());
	std::uniform_real_distribution<> uniformDistr(min, max);
	
	return( uniformDistr(gen) );
}

int Random_t::integer(int32_t min, int32_t max)
{
	std::random_device rd;  //Will be used to obtain a seed for the random number engine
	std::mt19937 gen(rd()); //Standard mersenne_twister_engine seeded with rd()
	std::uniform_int_distribution<> distrib(min, max);

	return distrib(gen);

}

double Random_t::logNormal(double mean, double std)
{
	std::random_device rd;
	std::mt19937 gen(rd());
	std::lognormal_distribution<double> logNormalDistr(mean,std);
	
	return( logNormalDistr(gen) );
}

double Random_t::rayleigh(double sd)
{
	std::random_device rd;
	std::mt19937 gen(rd());
	std::uniform_real_distribution<> rayleighNumber(0.0, 1.0);
	
	double number = rayleighNumber(gen);
	
	return( sd * sqrt(-2.0*log(number)) );
}

void Random_t::test(uint32_t totalPoints, const std::string& pathFileOut, bool exitAtFinish)
{
	double numberExpo, numberLogNormal, numberRayleigh;
	std::stringstream sOut;
		
	sOut << "exponential\tlognormal\trayleigh\n";

	for(size_t i = 0; i < totalPoints; i++){	
		numberExpo      = Random_t::exponential(1.0/5.0);
		numberLogNormal = Random_t::logNormal(6.383,0.1655);
		numberRayleigh  = Random_t::rayleigh(1.0);
		
		sOut << numberExpo << "\t" << numberLogNormal << "\t" << numberRayleigh << "\n";
	}
	
	std::ofstream outClearFile(pathFileOut);
	outClearFile << sOut.str();
	outClearFile.close();
	
	if(exitAtFinish){
		exit(EXIT_SUCCESS);
	}
	
}