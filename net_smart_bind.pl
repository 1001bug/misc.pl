#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use File::Basename;

sub help {
    my $msg = shift;
    say <<"HELP";
Bind devices irq to cpu by policy from right numa
\t-d[evice] <name> - filter basename of `find /proc/irq/[0-9]* -mindepth 1 -maxdepth 1 -type d`
\t-t[est] - default show current binds only. If set - show what would be set. Can be used to test before real set. Too strict Cpu filter may make set to fail.
\t-c[pu] - cpu list like 1-5,10-14,20 or 1,3,5,7 or 3-7 to filter all available NUMAs
\t-s[et] - set new value
\t-p[olicy] - single (def) set one cpu to each irq in round robin manner, all - set all cpus from corresponding device numa

Must run under root to have access to smp_affinity_list files even for read.
HELP
    say $msg if defined $msg;
    exit -1;
}

#convert list like 1-5,10-14,20 or 1,3,5,7 or 3-7 to array
sub parce_cpu_list {
    my $list = shift;

    #    say $list;
    die "Empty cpu list" unless defined $list;
    die "Wrong cpu list" if $list =~ /[^-,;\s\d]/;

    my @cpu = map {
        if   (/(\d+)\-(\d+)/) { $1 .. $2 }
        else                  { $_ }
    } split /[,;\s]+/, $list;
    return wantarray ? @cpu : join ' ', @cpu;
}

#read one line from file
sub read_one_line {
    my $path = shift;
    open my ($F), '<', $path or die "read from $path failed: $!";
    my $line = <$F>;
    close($F);
    chomp($line);
    return $line;
}

#if run without params - show help
help() unless (@ARGV);

#filter device name by
my $dev = '';

# 1 - show cur bunf, -1 - what-if, 0 - realy set
my $readonly = 1;

#throw all numa cpu filter range
my %cpu_filter = ();

# single all slide-windows?
my $policy = 'single';

#parce run params START
while ( my $key = shift ) {

    if ( $key =~ /^-d(evice)?/ ) {
        $dev = shift or help "Device not set!";
    }
    elsif ( $key =~ /^-t(est)?/ ) {
        $readonly = -1;
    }
    elsif ( $key =~ /^-s(et)?/ ) {
        $readonly = 0;
    }
    elsif ( $key =~ /^-p(olicy)?/ ) {
        $policy = shift or help "Policy not passed!";
        given ($policy) {
            when ('single') {
                say "Policy '$policy': each irq gets one cpu from right numa in round robin"
            }
            when ('all') { say "Policy '$policy': each irq gets all cpu range from right numa" }

    #           when('slide') {say "each irq gets shifting to right cpu range "}
            default { help "Wrong policy '$policy'" }
        }
    }
    elsif ( $key =~ /^-c(pu)?/ ) {
        my $cpus = shift or help "Cpu list not passed!";
        map { $cpu_filter{$_} = 1 } parce_cpu_list($cpus);
    }
    else {
        help
"cmd key '$key' not known.";
    }
}

#parce run params END

#minimal run params - device name
help "Device not set" unless length($dev);

#say hello
say "Device filter $dev, policy $policy, cpu_filter '"
  . join( ',', sort { $a <=> $b } keys %cpu_filter )
  . "', mode "
  . ( $readonly == 0 ? 'SET' : 'readonly/test' );

#numa to cpu list hash
my %NUMA = ();

# map {
#     $NUMA{ int($1) } =
#       +[ ( grep { $_ >= $min_cpu && $_ <= $max_cpu } split /\s+/, $2 ) ]
#       if /node (\d+) cpus: ([\d\s]+)/
# } qx*numactl -H* or die "cannot run 'numactl -H': $!";
#

map {
    $NUMA{ int($1) } = +[
        (
            grep { %cpu_filter ? defined $cpu_filter{$_} : 1 }
              parce_cpu_list($2)
        )
      ]
      if /NUMA node(\d+) CPU\(s\):\s+([-,\d]+)/
} qx*lscpu | grep -P 'NUMA node\\d+ CPU'* or die "cannot run 'lscpu': $!";

say "Numa-cpu layout" . ( %cpu_filter ? ' after filter' : '' );

for ( sort { $a <=> $b } keys %NUMA ) {
    say "num # $_: " . join ' ', @{ $NUMA{$_} };
}

#path '/proc/irq/NN' to real device name hash
my %irq_path =
  map { chomp($_); dirname($_) => basename($_) }
  grep { basename($_) =~ /$dev/o }
  qx{find /proc/irq/[0-9]* -mindepth 1 -maxdepth 1 -type d}
  or die "cannot find any device by '$dev' in  /proc/irq/";

#never trigger, just for safe
help "No device found by $dev" unless ( keys %irq_path );

#for nice aligned device and irq path print remember max string len
my $max_dev_name = 0;
my $max_irq_path = 0;

map { my $l = length($_); $max_irq_path = $l if $l > $max_irq_path }
  keys %irq_path;
map { my $l = length($_); $max_dev_name = $l if $l > $max_dev_name }
  values %irq_path;

#sort by NN in '/proc/irq/NN' and go throw it for show|test|set
for (
    map  { $_->[0] }
    sort { $a->[1] <=> $b->[1] }
    map  { [ $_ => $_ =~ /\/proc\/irq\/(\d+)/ ] }
    keys %irq_path

  )
{

    my $path_smp  = "$_/smp_affinity_list";
    my $path_node = "$_/node";

    my $device = sprintf "%-*s", $max_dev_name, $irq_path{$_};
    my $path_smp_t = sprintf "%-*s", $max_irq_path + 18, $path_smp;

    my $node     = read_one_line($path_node);
    my $cur_bind = read_one_line($path_smp);

    say "NUMA $node, Dev $device irq path $path_smp_t current bind $cur_bind";

    #if set or test - go into
    if ( $readonly <= 0 ) {
        my $new_bind;

        #by policy - prepare new value
        if ( length($policy) == 0 || $policy eq 'single' ) {
            my $n = shift @{ $NUMA{$node} };
            die "Wrong numa node $node or empty cpu list" unless defined $n;
            push @{ $NUMA{$node} }, $n;
            $new_bind = "$n";
        }
        elsif ( $policy eq 'all' ) {
            my $n = join ',', @{ $NUMA{$node} };
            die "Wrong numa node $node or empty cpu list" unless length($n);
            $new_bind = "$n";
        }

        say "NUMA $node, Dev $device irq path $path_smp_t "
          . ( $readonly < 0 ? 'would' : '   do' )
          . " set to $new_bind (policy $policy)";

        #   if ( $readonly <= 0 );

        #if is SET - write new value
        unless ($readonly) {
            open my $F, '>', $path_smp
              or die "Cannot open $path_smp for write: $!";
            say $F $new_bind;
            close($F);

        }    #if set
    }
}

