package Plugins::Zvuk::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::Zvuk::API;
use Plugins::Zvuk::Browse;
use Plugins::Zvuk::ProtocolHandler;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.zvuk',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_ZVUK',
} );

my $prefs = preferences('plugin.zvuk');

sub initPlugin {
	my $class = shift;

	$prefs->init( {
		token   => '',
		quality => 'flac',
		email   => '',
	} );

	$class->SUPER::initPlugin(
		feed   => \&Plugins::Zvuk::Browse::handleFeed,
		tag    => 'zvuk',
		menu   => 'radios',
		is_app => 1,
		weight => 10,
	);

	if ( main::WEBUI ) {
		require Plugins::Zvuk::Settings;
		Plugins::Zvuk::Settings->new;
	}

	Slim::Player::ProtocolHandlers->registerHandler(
		zvuk => 'Plugins::Zvuk::ProtocolHandler'
	);

	main::DEBUGLOG && $log->is_debug && $log->debug('Zvuk plugin initialized');
}

sub postinitPlugin {
	my $class = shift;

	return unless $prefs->get('token');

	Plugins::Zvuk::API::validateToken(
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug('Zvuk token is valid');
		},
		sub {
			$log->warn('Zvuk token validation failed — check plugin settings');
		},
	);
}

sub getDisplayName { return 'PLUGIN_ZVUK' }

sub playerMenu { }

1;
