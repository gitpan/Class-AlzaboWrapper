# t/01_ini.t; just to load Class::AlzaboWrapper by using it

$|++; 
print "1..1
";
my($test) = 1;

# 1 load
use Class::AlzaboWrapper;
my($loaded) = 1;
$loaded ? print "ok $test
" : print "not ok $test
";
$test++;

# end of t/01_ini.t

