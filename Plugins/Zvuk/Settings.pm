package Plugins::Zvuk::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

use Plugins::Zvuk::API;

my $log   = logger('plugin.zvuk');
my $prefs = preferences('plugin.zvuk');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_ZVUK');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/Zvuk/settings/basic.html');
}

sub prefs {
	return ( $prefs, qw(token quality email) );
}

sub _finishHandler {
	my ( $class, $client, $params, $callback, @args ) = @_;
	my $body = $class->SUPER::handler( $client, $params );
	$callback->( $client, $params, $body, @args ) if $callback;
	return $body;
}

sub _saveToken {
	my ( $class, $client, $params, $callback, $token, @args ) = @_;

	$prefs->set( token => $token );

	Plugins::Zvuk::API::validateTokenAsync(
		$token,
		sub {
			$params->{warning} = string('PLUGIN_ZVUK_LOGIN_OK');
			$params->{isSignedIn} = 1;
			$class->_finishHandler( $client, $params, $callback, @args );
		},
		sub {
			$prefs->remove('token');
			$params->{warning} = string('PLUGIN_ZVUK_TOKEN_INVALID');
			$params->{isSignedIn} = 0;
			$class->_finishHandler( $client, $params, $callback, @args );
		},
	);
}

sub handler {
	my ( $class, $client, $params, $callback, @args ) = @_;

	if ( $params->{signout} ) {
		$prefs->remove('token');
		$params->{warning} = string('PLUGIN_ZVUK_SIGNED_OUT');
		$params->{isSignedIn} = 0;
		return $class->_finishHandler( $client, $params, $callback, @args );
	}

	if ( $params->{signin} ) {
		my $email    = $params->{pref_email} // '';
		my $password = $params->{pref_password} // '';
		$email =~ s/^\s+|\s+$//g;

		if ( !$email || !$password ) {
			$params->{warning} = string('PLUGIN_ZVUK_LOGIN_EMPTY');
			return $class->_finishHandler( $client, $params, $callback, @args );
		}

		$prefs->set( email => $email );

		Plugins::Zvuk::API::loginByEmailAsync(
			$email,
			$password,
			sub {
				my $token = shift;
				$class->_saveToken( $client, $params, $callback, $token, @args );
			},
			sub {
				$params->{warning} = string('PLUGIN_ZVUK_LOGIN_FAILED');
				$params->{isSignedIn} = $prefs->get('token') ? 1 : 0;
				$class->_finishHandler( $client, $params, $callback, @args );
			},
		);
		return;
	}

	if ( $params->{saveManualToken} ) {
		my $token = $params->{pref_token} // '';
		$token =~ s/^\s+|\s+$//g;

		if ( !$token ) {
			$params->{warning} = string('PLUGIN_ZVUK_TOKEN_EMPTY');
			return $class->_finishHandler( $client, $params, $callback, @args );
		}

		$class->_saveToken( $client, $params, $callback, $token, @args );
		return;
	}

	if ( $params->{saveSettings} ) {
		if ( my $quality = $params->{pref_quality} ) {
			$prefs->set( quality => $quality ) if $quality =~ /^(?:flac|high|mid)$/;
		}

		$params->{warning} = string('PLUGIN_ZVUK_TOKEN_SAVED') if $prefs->get('token');
		return $class->_finishHandler( $client, $params, $callback, @args );
	}

	return $class->SUPER::handler( $client, $params );
}

sub beforeRender {
	my ( $class, $params ) = @_;

	my $token = $prefs->get('token');
	$params->{hasToken}   = $token ? 1 : 0;
	$params->{isSignedIn} = $token ? 1 : 0;
	$params->{profileUrl} = Plugins::Zvuk::API::PROFILE_URL();
	$params->{savedEmail} = $prefs->get('email') || '';
}

1;
