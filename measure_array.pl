#!/usr/bin/perl

=pod 
break each line by separator, take n-th (zero) sort, calc stat for all lines

=cut


use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

my @data;
my $field=0;
my $sum=0;
my $min;
my $max;
my $sep='\s+';
my $table = 1;
my $positiv_only=0;

#if ((-t)){
#print "STDIN ONLY!!! Usage -f fieldN -s separator -t|-T table or linear output <file";
#exit 0;}



while(my $key=shift){

	if($key =~/^-f(\d+)?/){
		if(defined $1){
			$field=int($1);
		}else{
		$field=shift or die "Field number not set!";
		}
	}
	elsif($key eq "-s"){
		$sep=shift or die "Separator not set!";
	}
	elsif($key eq "-t"){ #nice table
		$table = 1;
	}elsif($key eq "-l"){ #just list
		$table = 0;
	}elsif($key eq "-p"){ #positiv only
		$positiv_only=1;
	}
	else{
		#print  STDERR "Key '$key' not known\n";
		unshift @ARGV,$key;
		last;
	}
}
unless(@ARGV){

die "Empty file list and no STDIN..." if(-t);
}

#printf("Filed %i, separator '%s'\n",$field,$sep);

while(<>){
	my @t=split /$sep/;
	if(@t > $field){

	my $v=int($t[$field]);
	
	if(looks_like_number $t[$field]){
	next if($positiv_only==1 && $v<0);
	push @data,$v;
	$sum+=$v;
	}
	}
}#while

my $size=@data;

die "Nothig found! Separator?" unless $size>0;

@data = sort {$a <=> $b} @data;



#min non zero val!!!!
for(my $n=0;$n<$size;$n++){
	if($data[$n]>0){
	$min =$data[$n];
	last;
	}
}


$max=$data[-1];

my @TABLE=();

#push @TABLE, +{L => 'MIN',F => '%i',V => $min,W => 0,};
push @TABLE, +{L => 'MIN',F => '%i',V => $data[0],W => 0,};
push @TABLE, +{L => 'P01',F => '%i',V => $data[$size*0.01],W => 0,};
push @TABLE, +{L => 'P05',F => '%i',V => $data[$size*0.05],W => 0,};
push @TABLE, +{L => 'P25',F => '%i',V => $data[$size*0.25],W => 0,};
push @TABLE, +{L => 'MEDIAN',F => '%i',V => $data[$size*0.5],W => 0,};
push @TABLE, +{L => 'P75',F => '%i',V => $data[$size*0.75],W => 0,};
push @TABLE, +{L => 'P95',F => '%i',V => $data[$size*0.95],W => 0,};
push @TABLE, +{L => 'P99',F => '%i',V => $data[$size*0.99],W => 0,};
push @TABLE, +{L => 'P999',F => '%i',V => $data[$size*0.999],W => 0,};
push @TABLE, +{L => 'P9999',F => '%i',V => $data[$size*0.9999],W => 0,};
push @TABLE, +{L => 'MAX',F => '%i',V => $data[-1],W => 0,};
push @TABLE, +{L => 'AVG',F => '%.3f',V => $sum/$size,W => 0,};
push @TABLE, +{L => 'CNT',F => '%i',V => $size,W => 0,};

for(@TABLE){
	$_->{V} = sprintf $_->{F},$_->{V};
	#max width: lable or formated value
	($_->{W}) = sort {$b <=> $a} length($_->{V}),length($_->{L});
}



#PRINT RESULT

if($table){
	my $hdelim='';

	for(@TABLE){
		$hdelim.= '+-'.('-' x $_->{W}).'-';
	}
	$hdelim.="+\n";

	print $hdelim;

	for(@TABLE){
		printf "| %*s " ,$_->{W},$_->{L};
	}
	print "|\n";

	print $hdelim;

	for(@TABLE){
		printf "| %*s " ,$_->{W},$_->{V};
	}
	print "|\n";
	print $hdelim;
}
## NOT TABLE - LIST

else{
	for(@TABLE){
		printf "%-*s " ,$_->{W},$_->{L};
	}
	print "\n";



	for(@TABLE){
		printf "%-*s " ,$_->{W},$_->{V};
	}
	print "\n";

}#else (not table)




















#(reverse join '`', unpack '(A3)*', reverse $size));

