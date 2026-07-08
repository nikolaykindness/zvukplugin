package Plugins::Zvuk::Importer;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::Zvuk::API;

my $log   = logger('plugin.zvuk');
my $prefs = preferences('plugin.zvuk');

sub needsUpdate {
	my ( $class, $cb ) = @_;
	$cb->( Plugins::Zvuk::API::getToken() ? 1 : 0 );
}

sub startScan {
	my ( $class ) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('Zvuk importer scan started');
}

sub endScan {
	my ( $class ) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('Zvuk importer scan finished');
}

sub getLibraryStats {
	return 0;
}

1;
