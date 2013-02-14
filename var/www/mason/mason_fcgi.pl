#!/usr/bin/env perl
 
use strict;
use warnings;
use lib 'lib';
use Getopt::Long;

my %SITES = ( 'debian.localdomain' => 'site1' );
 
my $LOGFILE = "/var/log/nginx/fcgi/fcgi.log";
my $WORKSPACE = "/var/www/mason/workspace";
my $PIDFILE = "/var/run/fcgi/fcgi.pid";
my $BASEDIR = "/var/www";
my $ERROR_URI = "/errors/503.html";
my $LISTEN_QUEUE = 100;
my ($DEFAULT_HOST) = keys %SITES;
my $DEBUG = 0;

my $HELP;

BEGIN {
  my ($socket);

  GetOptions( 
              'help' => \$HELP,
	         'pid=s' => \$PIDFILE,
	         'log=s' => \$LOGFILE,
	       'debug=s' => \$DEBUG,
	      'socket=s' => \$socket,
	     'basedir=s' => \$BASEDIR,
	   'workspace=s' => \$WORKSPACE,
	   'error-uri=s' => \$ERROR_URI,
	'listen-queue=s' => \$LISTEN_QUEUE,
	'default-host=s' => \$DEFAULT_HOST

  );
  $ENV{FCGI_SOCKET_PATH} ||= '/var/run/fcgi/mason_fcgi.sock';
  $ENV{FCGI_SOCKET_PATH} = $socket if $socket;
  $ENV{FCGI_LISTEN_QUEUE} ||= $LISTEN_QUEUE;
}

if ($HELP) {
	my ($me) = $0 =~ m{.*/(.*)};
	print "$me [--help] [--pid=$PIDFILE] [--log=$LOGFILE] [--debug]"
		." [--socket=$ENV{FCGI_SOCKET_PATH}]"
		." [--basedir=$BASEDIR] [--workspace=$WORKSPACE]"
		." [--error-uri=$ERROR_URI] [--listen-queue=$LISTEN_QUEUE] "
		." [--default-host=$DEFAULT_HOST]\n";
	exit 0;
}
 
use CGI::Fast;
use HTML::Mason::CGIHandler;
use Cwd;
use IO::All;

#########################################################################
#
#
{
    package HTML::Mason::Commands;
	# use My::Own::Module;
	# use Data::Dumper;

    # anything you want available to components                                
    use vars(qw($DBH %stash));
}

##########################################################################

sub HTML::Mason::FakeApache::document_root {
    my $self = shift;
    return $ENV{DOCUMENT_ROOT};
}

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
	return unless $DEBUG;
    my ($log_file, $log_message) = @_;
    my $curr_time = logformat();
    my $write_message = "[$curr_time]   $log_message";
    $write_message >> io($log_file);
    "\n" >> io($log_file);
}


##########################################################################
 
"\n\n" >> io($LOGFILE) if $DEBUG;

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

### Create the Mason handlers per site
my %handlers;
 
while (my ($site, $comp_base) = each %SITES) {
  $handlers{$site} = HTML::Mason::CGIHandler->new(
    comp_root => "$BASEDIR/$comp_base",
    data_dir => "$WORKSPACE/$comp_base",
    error_mode => 'output',
  );
  addlog($LOGFILE,"$site:comp_base=$BASEDIR/$comp_base"
				.", data_dir=$WORKSPACE/$comp_base");
}
 
### request loop: foreach one, decide which vhost is the target, and call appropriate handler
while (my $cgi = new CGI::Fast()) {

  my ($host) = $ENV{HTTP_HOST} =~ /^(.+?)(:\d+)?$/;
  addlog($LOGFILE,">> HIT for '$host' => '$ENV{REQUEST_URI}'");

  if ( ! $SITES{$host} ) {
 	$ENV{REQUEST_URI} = $ERROR_URI;
	addlog($LOGFILE,">> Uknown site $host. It should be added to $0");
	$host = $DEFAULT_HOST;
  }
 
  ### Make sure we have a clean stash when we start
  %HTML::Mason::Commands::stash = ();
  
  $ENV{SCRIPT_NAME} = '';
  $cgi->path_info($ENV{DOCUMENT_URI});

  eval { $handlers{$host}->handle_cgi_object($cgi) };
  if (my $raw_error = $@) {
    addlog($LOGFILE,$raw_error);
  }
  
  ### And release the stash after the request
  %HTML::Mason::Commands::stash = ();
}

exit 0;
