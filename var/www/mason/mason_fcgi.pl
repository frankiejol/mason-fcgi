#!/usr/bin/env perl
 
use strict;
use warnings;
use lib 'lib';
use Getopt::Long;
 
my $LOGFILE = "/var/log/nginx/fcgi/fcgi.log";
my $WORKSPACE = "/var/www/mason/workspace";
my $PIDFILE = "/var/run/fcgi/fcgi.pid";
my $BASEDIR = "/var/www";

BEGIN {
  my $socket;
  GetOptions( 
	   'pid=s' => \$PIDFILE,
	   'log=s' => \$LOGFILE,
	'socket=s' => \$socket,
	'basedir=s'=> \$BASEDIR,
	'workspace=s' => \$WORKSPACE,

  );
  $ENV{FCGI_SOCKET_PATH} ||= '/var/run/fcgi/mason_fcgi.sock';
  $ENV{FCGI_SOCKET_PATH} = $socket if $socket;
  $ENV{FCGI_LISTEN_QUEUE} ||= 10;
}
 
use CGI::Fast;
use HTML::Mason::CGIHandler;
use Cwd;
use IO::All;

##########################################################################
sub addzero {
    my ($date) = shift;
    if ($date < 10) {
        return "0$date";
    }
       return $date;
}

sub logformat {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$iddst) = localtime(time);
    my $datestring;
    $year += 1900;
    $mon++;
    $mon  = addzero($mon);
    $mday = addzero($mday);
    $min  = addzero($min);
    $datestring = "$year-$mon-$mday $hour:$min";
    return($datestring);
}

sub addlog {
    my ($log_file, $log_message) = @_;
    my $curr_time = logformat();
    my $write_message = "[$curr_time]   $log_message";
    $write_message >> io($log_file);
    "\n" >> io($log_file);
}


##########################################################################
 
"\n\n" >> io($LOGFILE);
addlog($LOGFILE,"Starting $0");
addlog($LOGFILE,"Running with $> UID");
addlog($LOGFILE,"Perl $]");
addlog($LOGFILE, "Deamon listening at UNIX socket $ENV{FCGI_SOCKET_PATH}");

if ( -e $PIDFILE) {
        print "\n\tERROR\t PID file $PIDFILE already exists\n\n";
        addlog($LOGFILE, "Can not use PID file $PIDFILE, already exists.");
        exit 1;
}

my $pid = fork();

if( $pid ) {
	addlog($LOGFILE,"Forking worker process with PID $pid");
	$pid > io($PIDFILE);
	addlog($LOGFILE,"Parent process $$ is exiting");
    exit 0;
}

### All the vhosts we support. For each one specify the override comp_root
my %sites = (
  'site1.example.com' => 'site1',
);
 
### Create the Mason handlers per site
my %handlers;
 
while (my ($site, $comp_base) = each %sites) {
  $handlers{$site} = HTML::Mason::CGIHandler->new(
    comp_root => "$BASEDIR/$comp_base",
#      [[$comp_base => "$base/$comp_base"], [master => "$base/master"],],
    data_dir => $WORKSPACE,
    error_mode => 'output',
  );
  addlog($LOGFILE,"$site:comp_base=$BASEDIR/$comp_base, data_dir=$WORKSPACE");
}
 
{
  ### Usefull debug commands in the component namespace
  package HTML::Mason::Commands;
  use Data::Dumper;
  use vars qw( %stash );
}
 
### Preserve our stderr for logging
 
### request loop: foreach one, decide which vhost is the target, and call appropriate handler
while (my $cgi = new CGI::Fast()) {
  my ($host) = $ENV{HTTP_HOST} =~ /^(.+?)(:\d+)?$/;
  addlog($LOGFILE,">> HIT for '$host' => '$ENV{REQUEST_URI}'");
 
  ### Make sure we have a clean stash when we start
  %HTML::Mason::Commands::stash = ();
  
  # hand off to mason
  # FIXME: need to deal with unknown sites
  $cgi->path_info($ENV{REQUEST_URI});
  eval { $handlers{$host}->handle_cgi_object($cgi) };
  if (my $raw_error = $@) {
    addlog($LOGFILE,$raw_error);
  }
  
  ### And release the stash after the request
  %HTML::Mason::Commands::stash = ();
}

exit 0;
