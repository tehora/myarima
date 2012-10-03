#!/usr/bin/env perl
# file: 
#  
#    Copyright 2012 Dorota Celińska <tehora at jakilinux dot org>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>

use encoding 'utf8';
use strict;
use warnings;

sub warning {
    print <<EOM;
    myarima, made to simplify choosing the right arima/sarima model
    myarima Copyright (C) 2012 Dorota Celinska
    This program comes with ABSOLUTELY NO WARRANTY.
    This is free software, and you are welcome
    to redistribute it under certain conditions.
    For details see COPYING file.
    
EOM
}    

#basic arguments
#datadir - the dataset's directory
#variable - variable which best model ought to be found
#sample - the lenght of forecast  

my $datadir = "$ARGV[0]";
my $variable = "$ARGV[1]";
my $sample = "$ARGV[2]";

#creates .inp file
#to obtain the corrgram in output

#TO DO : mozliwosc wybierania okresu 4 12 lub inne

sub createCorrgramInpFile {

    open FILE, ">cor.inp" or die $!;

    print FILE <<EOM;
    open $datadir
    setobs 12 1992:01 --time-series
    corrgm $variable 30
    
EOM
    
    close FILE;
} 

#open gretcli and procede .inp
#the output will be written in cor.out file

sub corrgram2gretlcli{
    
    my $command = "gretlcli -b cor.inp  >cor.out";
    system($command);
    
}

#the general function to procede .inp files in gretl
#name = the name of the .inp file
#output written in the file.out file

sub script2gretlcli{
 
    my $name = shift;
    my $command = "gretlcli -e -b $name >>file.out";
    system($command);
}

#integration level
my $id=0;

#create .inp file for gretlcli with arima parameters
#output will be written in arima.inp file
#givenAR - lags for AR
#givenMA - lags for MA

#to do -- opcjonalnie podproba!

sub createArimaInp{
    
    my ($givenAR, $givenMA) = @_; 

    open FILE, ">arima.inp" or die $!;
	if ($_[1] ne "0") {
		print FILE <<EOM;
		open $datadir
		setobs 12 1992:01 --time-series
		smpl proba_ogolnie < $sample --restrict
		arima {$_[0]} 0 {$_[1]} ; $variable
		modtest --normality
    
EOM
	} else {
		print FILE <<EOM;
		open $datadir
		setobs 12 1992:01 --time-series
		smpl proba_ogolnie < $sample --restrict
		arima {$_[0]} 0 $_[1] ; $variable
		modtest --normality
    
EOM
	}
    close FILE;
}

#using gretl to procede possible models

sub arima{
	
  #if the file.out exists, remove it
  
  if (-e 'file.out') {
	unlink("file.out");
  }
  
  #system command: print the cor.out (corrgram)
  #and simultanously using awk print the 1st (number of lag) 
  #and the 3rd (significance of acf) collumn of the output where the * occurs
  #in the meantime using awk if the * occurs print the first collumn
  #and using grep choose the first 8 rows
  #in the meantime use tr and replace "\n" with " "
  #those will be the maximum lags from acf function
  
  my $acf = `cat cor.out | awk '/\*/ { print \$1\" \"\$3 }' | awk '/\*/ { print \$1 }' | grep -m 8 \"\.\" | tr '\n' '\ '`;
  
  #system command: print the cor.out (corrgram)
  #and simultanously using awk print the 1st (number of lag)
  #and the 2nd last collumn (significance of pacf) of the output where the * occurs
  #in the meantime using awk if the * occurs print the first collumn
  #and using grep choose the first 8 rows
  #in the meantime use tr and replace "\n" with " "
  #those will be the maximum lags from pacf function
  
  my $pacf = `cat cor.out | awk '/\*/ { print \$1\" \"\$ (NF - 2) }' | awk '/\*/ { print \$1 }' | grep -m 8 \"\.\" | tr '\n' '\ '`;

  #split the string into the list
  #acf for AR lags
  #pacf for MA lags
  
  my @oddsAR = split(/\ /, $acf);
  my @oddsMA = split(/\ /, $pacf);

  #Start with iterator equal to the lenght of possible lags for MA
  
  for (my $i=$#oddsMA; $i>=-1; $i--) {
	  
	  my $MA;
	  if ($i==-1) {
			$MA = "0";  
	  } else {
			#join the elements from list oddsMA up to the ith element (space is a separator) 	
			$MA = join(' ', @oddsMA[0..$i]);
	  }
	  
      #second loop against the lenght of possible ARs
      
      for (my $j=$#oddsAR; $j>=-1; $j--) {
			
			#enabling models ar(0)ma(...) ar(...)ma(0) but preventing from ar(0)ma(0)
			
			my $AR;
			if ($j==-1) {
				if ($i!=-1) {
					$AR = "0";
				} else {
					last;
				}			
			} else {
			#join the elements from list oddsAR up to the jth element (space is a separator)	
			$AR = join(' ', @oddsAR[0..$j]); 
			}
			
			#after choosing the parameters make the .inp and then procede it with gretlcli
			
			createArimaInp($AR,$MA);
			script2gretlcli("arima.inp");
     }
  }

}

my @data;

#remove possible errors in the file.out file
sub killErrors{
	
    #seek for convergence or Failed in the file.out (if found insert the previous line into lol)
	
   `cat file.out | sed -n '/convergence/{g;1!p;};h' > lol`;
   `cat file.out | sed -n '/Failed/{g;1!p;};h' >> lol`;
   
   #insert cat lol into variable klol
   my $klol = `cat lol`;
	
	#if the failed models occured (so their names are in klol) do the following
	
	if ($klol =~ /\?\ arima/) {
		#extract the numbers of wrong lines:
		#print the file.out in the meantime using fgrep search the lines from lol and insert their line numbers
		#in the meantime using awk print the first column of the line
		#in the meantime using sed replace globally : with nothing and replace ? with nothing globally
		#in the meantime using tr replace \n with space 
        my $badnumbers = `cat file.out | fgrep -f lol -n | awk '{print \$1}' | sed -e 's/://g' -e 's/\?//g' | tr '\n' '\ '`;
        
        # create the list MagicNumbers by splitting badnumbers (space as the separator)
        my @MagicNumbers = split(/\ /, $badnumbers);
        
        #we need those numbers sorted
        my @prettyMN = sort {$a <=> $b} @MagicNumbers;
        
        #candle is the lenght of a sorted list
        my $candle = @prettyMN;
		
		
        for (my $dj=0; $dj<$candle; $dj++) {
			
			#decrease the djth element of sorted list with the value of the iterator
			#then replace the beginning with the string | sed
			#then replace the end with d
            $prettyMN[$dj]= ($prettyMN[$dj]-$dj);
            $prettyMN[$dj] =~ s/^/|\ sed\ /;
            $prettyMN[$dj] =~ s/$/d/;
        }
			#join the list into one string (space is a separator)
			 
        my $finalRemove = join(' ', @prettyMN);
        
        #great one-liner ^^ in fact we remove the lines with names of failed models!
        #the output is file2.out
        
        `cat file.out $finalRemove > file2.out`;
  
    } else {
       #if there were no failed models
       `cp file.out file2.out`;
    }
}

#extract names of the models and their BIC and AIC criteria
#there should be also p-value of test whether the rests are 
#white noise but the implemented test in gretl is not appropriate

sub insertPossibleModels{ 
	
	#count the instances of "? arima" in file2.out 
    my $size= `cat file2.out | grep "\?\ arima" -c`;
    
    for (my $i=1; $i<=$size; $i++ ) {
        my $ip =$i."p";
        
        #@data is the array of hashes
        #the 1st element is the name of the model
        #the 2nd element is the Schwarz criterion (BIC)
        #the 3rd element is the Akaike criterion (AIC)
        #the 4th element should be p-value (whether the rests are a white noise)
        
        push @data, {
			
			#find lines containing "? arima" and insert it into model - only ith presence
			#find the ith BIC and AIC and p-value
			 
            model => `cat file2.out | grep "\?\ arima" | sed -n "$ip"`, 
            bic => `cat file2.out | awk '/Schwarz\ criterion/ {print \$3 }' | sed -n "$ip"`, 
            aic => `cat file2.out | awk '/Akaike\ criterion/ {print \$5 }' | sed -n "$ip"`, 
            pvalue => `cat file2.out | awk '/with\ p-value/ {print \$6}' | sed -n "$ip"` };
    }
}

sub returnRightModel{

	my @sorted =  sort { $$a{'bic'} <=> $$b{'bic'} } @data;
	
	#there's a possibility for choosing model with lowest information criteria
	#and rests being white noise at the same time
	#but the appropiate test has to be implemented (white noise is not equal to normal distribution)
	
	my $pivalju = 0;

	#my $size = `cat file2.out | grep "\?\ arima" -c`;
	
	#intuition: loop through the sorted array looking for p-values greater than 0.05 (standard level)
	#if found remember the number of the model and abort the loop
	
	#for (my $i=0; $i<=$size; $i++ ) {
	#	if ($sorted[$i]{pvalue} ge 0.05) {
	#		$pivalju = $i;
	#		last;
	#	} 
	#}

	if ($pivalju ne 0) {
		print "$sorted[$pivalju]{model}";
	} else {

		print "$sorted[0]{model}";
	}
}

#remove unnecessary files
sub cleanDisposableFiles {
	
	unlink("arima.inp") if (-e 'arima.inp');
	unlink("cor.inp") if (-e 'cor.inp');
	unlink("cor.out") if (-e 'cor.out');
	unlink("file.out") if (-e 'file.out');
	unlink("lol") if (-e 'lol');
}


warning();
createCorrgramInpFile();
corrgram2gretlcli();
arima();
killErrors();
insertPossibleModels();
returnRightModel();
#cleanDisposableFiles();
