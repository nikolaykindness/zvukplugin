package Plugins::Zvuk::ProtocolHandler;

use strict;
use warnings;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::Zvuk::API;

my $log   = logger('plugin.zvuk');
my $prefs = preferences('plugin.zvuk');

use constant URL_REGEXP => qr{^zvuk://([^/]+)/(.+)$};

sub explodePlaylist {
	my ( $class, $client, $url, $cb ) = @_;

	if ( $url =~ URL_REGEXP ) {
		my ( $type, $id ) = ( $1, $2 );

		if ( $type eq 'track' ) {
			return $cb->( [$url] );
		}

		if ( $type eq 'playlist' ) {
			require Plugins::Zvuk::API::Async;
			return Plugins::Zvuk::API::Async::getPlaylistTracks(
				$client,
				sub {
					my $result = shift;
					my @urls = map { $_->{url} } @{ $result->{items} || [] };
					$cb->( \@urls );
				},
				$id,
			);
		}
	}

	return $cb->( [$url] );
}

sub getNextTrack {
	my ( $class, $song, $successCb, $errorCb ) = @_;

	my $url = $song->currentTrack()->url;
	my ( $trackId ) = $url =~ m{^zvuk://track/(.+)$};

	unless ($trackId) {
		$log->warn("Invalid Zvuk URL: $url");
		return $errorCb->('Invalid Zvuk track URL');
	}

	my $quality    = Plugins::Zvuk::API::getQuality();
	my $streamUrl  = Plugins::Zvuk::API::getTrackUrl( $trackId, $quality );

	unless ($streamUrl) {
		# Fallback to lower quality if FLAC/high unavailable
		for my $fallback ( qw(high mid) ) {
			next if $fallback eq $quality;
			$streamUrl = Plugins::Zvuk::API::getTrackUrl( $trackId, $fallback );
			last if $streamUrl;
		}
	}

	unless ($streamUrl) {
		$log->error("No stream URL for track $trackId");
		return $errorCb->('Failed to get stream URL');
	}

	main::DEBUGLOG && $log->is_debug && $log->debug("Stream URL for $trackId: $streamUrl");

	$song->streamUrl($streamUrl);

	my $format = $quality eq 'flac' ? 'flc' : 'mp3';
	$song->pluginData( format => $format );

	Slim::Utils::Scanner::Remote::parseRemoteHeader(
		$song->track,
		$streamUrl,
		$format,
		sub {
			$successCb->();
		},
		sub {
			my ( $self, $error ) = @_;
			$log->warn("Could not parse $format header: $error");
			$successCb->();
		},
	);
}

sub new {
	my ( $class, $args ) = @_;

	my $streamUrl = $args->{song}->streamUrl() || return;

	main::DEBUGLOG && $log->is_debug && $log->debug("Remote streaming Zvuk: $streamUrl");

	return $class->SUPER::new( {
		url    => $streamUrl,
		song   => $args->{song},
		client => $args->{client},
	} );
}

sub formatOverride {
	my ( $class, $song ) = @_;
	return $song->pluginData('format') || 'mp3';
}

sub audioScrobblerSource { 'P' }

1;
