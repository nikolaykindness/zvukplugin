package Plugins::Zvuk::ProtocolHandler;

use strict;
use warnings;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Plugins::Zvuk::API;

my $log   = logger('plugin.zvuk');
my $prefs = preferences('plugin.zvuk');

use constant MP3_BITRATE_HIGH => 320_000;
use constant MP3_BITRATE_MID  => 128_000;

use constant LEGACY_URL_REGEXP => qr{^zvuk://([^/]+)/(.+)$};

sub crackUrl {
	my ( $class, $url ) = @_;
	return unless $url;

	my ( $id, $ext ) = $url =~ m{^zvuk://([^/.]+)\.(mp3|flac?)$}i;
	unless ($id) {
		( $id ) = $url =~ m{^zvuk://track/(.+)$};
		$ext = 'mp3';
	}

	my $format = ( $ext && $ext =~ /flac/i ) ? 'flc' : 'mp3';
	return ( $id, $format );
}

sub getFormatForURL {
	my ( $class, $url ) = @_;
	my ( undef, $format ) = $class->crackUrl($url);
	return $format || 'mp3';
}

sub formatOverride {
	my ( $class, $song ) = @_;
	return $song->pluginData('format') || 'mp3';
}

sub scanUrl {
	my ( $class, $url, $args ) = @_;
	$args->{cb}->( $args->{song}->currentTrack() );
}

sub requestString {
	my ( $self, $client, $url, $post, $seekdata ) = @_;

	my $request = $self->SUPER::requestString( $client, $url, $post, $seekdata );
	return $request unless $url;

	if ( my $token = $prefs->get('token') ) {
		my $extra = join "\r\n",
			'Referer: ' . Plugins::Zvuk::API::BASE_URL . '/',
			'Origin: ' . Plugins::Zvuk::API::BASE_URL,
			'X-Auth-Token: ' . $token,
			'Cookie: auth=' . $token;
		$request =~ s/\r\n\r\n/\r\n$extra\r\n\r\n/;
	}

	return $request;
}

sub explodePlaylist {
	my ( $class, $client, $url, $cb ) = @_;

	if ( $url =~ LEGACY_URL_REGEXP ) {
		my ( $type, $id ) = ( $1, $2 );

		if ( $type eq 'track' ) {
			return $cb->( [ Plugins::Zvuk::API::getTrackUri($id) ] );
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
	my ( $trackId ) = $class->crackUrl($url);

	unless ($trackId) {
		$log->warn("Invalid Zvuk URL: $url");
		return $errorCb->('Invalid Zvuk track URL');
	}

	my ( $streamUrl, $format ) = Plugins::Zvuk::API::getTrackStream($trackId);

	unless ($streamUrl) {
		$log->error("No stream URL for track $trackId");
		return $errorCb->('Failed to get stream URL');
	}

	main::DEBUGLOG && $log->is_debug && $log->debug("Stream URL for $trackId ($format): $streamUrl");

	$song->streamUrl($streamUrl);
	$song->pluginData( format => $format );
	$song->track->content_type($format);

	if ( $format eq 'mp3' ) {
		my $bitrate = $streamUrl =~ /streamhq/i ? MP3_BITRATE_HIGH : MP3_BITRATE_MID;
		$song->bitrate($bitrate);
		Slim::Music::Info::setBitrate( $song->track, $bitrate );
		return $successCb->();
	}

	Slim::Utils::Scanner::Remote::parseRemoteHeader(
		$song->track,
		$streamUrl,
		$format,
		sub { $successCb->() },
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

	my $sock = $class->SUPER::new( {
		url    => $streamUrl,
		song   => $args->{song},
		client => $args->{client},
	} ) || return;

	${*$sock}{contentType} = $args->{song}->pluginData('format') || 'mp3';

	return $sock;
}

sub audioScrobblerSource { 'P' }

1;
