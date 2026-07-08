package Plugins::Zvuk::API;

use strict;
use warnings;

use JSON::XS::VersionOneAndTwo;
use URI::Escape ();

use Slim::Networking::SimpleSyncHTTP;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $log   = logger('plugin.zvuk');
my $prefs = preferences('plugin.zvuk');

use constant BASE_URL    => 'https://zvuk.com';
use constant LOGIN_URL   => BASE_URL . '/api/tiny/login/email';
use constant STREAM_URL  => BASE_URL . '/api/tiny/track/stream';
use constant GRAPHQL_URL => BASE_URL . '/api/v1/graphql';
use constant USER_AGENT  => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

sub PROFILE_URL { return BASE_URL . '/api/tiny/profile' }

sub _baseHeaders {
	return (
		'User-Agent'      => USER_AGENT,
		'Accept'          => 'application/json, text/plain, */*',
		'Accept-Language' => 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
		'Referer'         => BASE_URL . '/',
		'Origin'          => BASE_URL,
	);
}

sub extractToken {
	my ($data) = @_;
	return unless $data && ref $data eq 'HASH';

	return $data->{result}{token}
		// $data->{user}{token}
		// $data->{result}{profile}{token}
		// $data->{token};
}

sub loginByEmail {
	my ( $email, $password ) = @_;
	return unless $email && $password;

	my $body = 'email=' . URI::Escape::uri_escape_utf8($email)
		. '&password=' . URI::Escape::uri_escape_utf8($password);

	my $result = Slim::Networking::SimpleSyncHTTP->new->post(
		LOGIN_URL,
		_baseHeaders(),
		'Content-Type' => 'application/x-www-form-urlencoded',
		$body,
	);

	if ( !$result->is_success ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Login failed: ' . $result->status_line);
		return;
	}

	my $data = _decodeJson( ${ $result->contentRef } );
	return extractToken($data);
}

sub loginByEmailAsync {
	my ( $email, $password, $cbOk, $cbFail ) = @_;

	unless ( $email && $password ) {
		return $cbFail->();
	}

	my $body = 'email=' . URI::Escape::uri_escape_utf8($email)
		. '&password=' . URI::Escape::uri_escape_utf8($password);

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $data = _decodeJson( ${ $response->contentRef } );
			my $token = extractToken($data);

			if ($token) {
				return $cbOk->($token);
			}

			main::DEBUGLOG && $log->is_debug && $log->debug('Login response without token');
			$cbFail->();
		},
		sub {
			$log->warn("Email login failed: $_[1]");
			$cbFail->();
		},
	);

	$http->post(
		LOGIN_URL,
		_baseHeaders(),
		'Content-Type' => 'application/x-www-form-urlencoded',
		$body,
	);
}

sub getToken {
	my $token = $prefs->get('token');
	return $token if $token;
	return;
}

sub getQuality {
	my $quality = $prefs->get('quality') || 'flac';
	return $quality if $quality =~ /^(?:flac|high|mid)$/;
	return 'flac';
}

sub _headers {
	my $token = getToken() || return;

	return (
		_baseHeaders(),
		'Content-Type' => 'application/json',
		'X-Auth-Token' => $token,
	);
}

sub _requestHeaders {
	my @headers = _headers();
	return unless @headers;

	my $token = getToken();
	push @headers, Cookie => "auth=$token";

	return @headers;
}

sub _decodeJson {
	my ($content) = @_;
	return unless defined $content && length $content;

	my $data = eval { decode_json($content) };
	if ($@) {
		main::DEBUGLOG && $log->is_debug && $log->debug("JSON decode error: $@");
		return;
	}
	return $data;
}

sub _apiError {
	my ($data, $context) = @_;
	if ( $data && ref $data eq 'HASH' && $data->{errors} ) {
		$log->warn("$context: " . encode_json($data->{errors}));
		return 1;
	}
	return;
}

sub validateToken {
	my ( $cbOk, $cbFail ) = @_;

	my @headers = _requestHeaders();
	return $cbFail->() unless @headers;

	my $result = Slim::Networking::SimpleSyncHTTP->new->get(
		PROFILE_URL(),
		@headers,
	);

	if ( !$result->is_success ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Profile request failed: ' . $result->status_line);
		return $cbFail->();
	}

	my $data = _decodeJson( ${ $result->contentRef } );
	if ( !$data ) {
		return $cbFail->();
	}

	my $token = extractToken($data);
	if ($token) {
		return $cbOk->($data);
	}

	return $cbFail->();
}

sub validateTokenAsync {
	my ( $token, $cbOk, $cbFail ) = @_;
	return $cbFail->() unless $token;

	my @headers = (
		_baseHeaders(),
		'Content-Type'   => 'application/json',
		'X-Auth-Token'   => $token,
		Cookie           => "auth=$token",
	);

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $data = _decodeJson( ${ $response->contentRef } );
			my $valid = extractToken($data) || $token;
			return $cbOk->($data) if $valid;
			$cbFail->();
		},
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug("Token validation failed: $_[1]");
			$cbFail->();
		},
	);

	$http->get( PROFILE_URL(), @headers );
}

sub graphql {
	my ( $query, $operationName, $variables ) = @_;

	my @headers = _requestHeaders();
	return unless @headers;

	my $payload = encode_json( {
		query         => $query,
		operationName => $operationName,
		variables     => $variables || {},
	} );

	my $result = Slim::Networking::SimpleSyncHTTP->new->post(
		GRAPHQL_URL,
		@headers,
		$payload,
	);

	if ( !$result->is_success ) {
		$log->warn("GraphQL $operationName failed: " . $result->status_line);
		return;
	}

	my $data = _decodeJson( ${ $result->contentRef } );
	return if _apiError( $data, $operationName );

	return $data->{data};
}

sub getTrackUrl {
	my ( $trackId, $quality ) = @_;
	$quality ||= getQuality();

	my @headers = _requestHeaders();
	return unless @headers;

	my $url = STREAM_URL . '?id=' . $trackId . '&quality=' . $quality;

	my $result = Slim::Networking::SimpleSyncHTTP->new->get(
		$url,
		@headers,
	);

	if ( !$result->is_success ) {
		$log->warn("Stream request failed for track $trackId: " . $result->status_line);
		return;
	}

	my $data = _decodeJson( ${ $result->contentRef } );
	return unless $data && ref $data eq 'HASH';

	return $data->{result}{stream};
}

sub search {
	my ($query) = @_;
	return [] unless defined $query && length $query;

	my $gql = <<'GQL';
query search($query: String, $limit: Int = 20) {
	search(query: $query) {
		tracks(limit: $limit) {
			items {
				id title duration
				artists { id title }
				release { id title image { src } }
			}
		}
		artists(limit: $limit) {
			items { id title image { src } }
		}
		releases(limit: $limit) {
			items {
				id title
				image { src }
				artists { id title }
			}
		}
	}
}
GQL

	my $data = graphql( $gql, 'search', { query => $query, limit => 20 } );
	return {} unless $data && $data->{search};

	return $data->{search};
}

sub getUserPlaylists {
	my $gql = <<'GQL';
query userPlaylists {
	collection {
		playlists { id }
	}
}
GQL

	my $data = graphql( $gql, 'userPlaylists', {} );
	return [] unless $data && $data->{collection};

	my $items = $data->{collection}{playlists} || [];
	return [] unless @$items;

	my @ids = map { $_->{id} } @$items;
	return [] unless @ids;

	my $detailGql = <<'GQL';
query getPlaylists($ids: [ID!]!) {
	getPlaylists(ids: $ids) {
		id title duration
		image { src }
	}
}
GQL

	my $detail = graphql( $detailGql, 'getPlaylists', { ids => \@ids } );
	return [] unless $detail && $detail->{getPlaylists};

	return $detail->{getPlaylists};
}

sub getPlaylistTracks {
	my ($playlistId) = @_;
	return [] unless $playlistId;

	my $gql = <<'GQL';
query getPlaylistTracks($id: ID!, $limit: Int = 100, $offset: Int = 0) {
	playlistTracks(id: $id, limit: $limit, offset: $offset) {
		id title duration
		artists { id title }
		release { id title image { src } }
	}
}
GQL

	my $data = graphql( $gql, 'getPlaylistTracks', {
		id     => "$playlistId",
		limit  => 100,
		offset => 0,
	} );

	return [] unless $data && $data->{playlistTracks};
	return $data->{playlistTracks};
}

sub getFavoriteTracks {
	my $gql = <<'GQL';
query userTracks($orderBy: TrackOrderByType, $orderDirection: OrderDirectionType) {
	collection {
		tracks(orderBy: $orderBy, orderDirection: $orderDirection) {
			id
		}
	}
}
GQL

	my $data = graphql( $gql, 'userTracks', {
		orderBy        => 'dateAdded',
		orderDirection => 'desc',
	} );

	return [] unless $data && $data->{collection};

	my $items = $data->{collection}{tracks} || [];
	return [] unless @$items;

	my @ids = map { $_->{id} } @$items;
	return [] unless @ids;

	my $tracksGql = <<'GQL';
query getTracks($ids: [ID!]!) {
	getTracks(ids: $ids) {
		id title duration
		artists { id title }
		release { id title image { src } }
	}
}
GQL

	my $tracks = graphql( $tracksGql, 'getTracks', { ids => \@ids } );
	return [] unless $tracks && $tracks->{getTracks};

	return $tracks->{getTracks};
}

sub trackToItem {
	my ( $track ) = @_;
	return unless $track && ref $track eq 'HASH' && $track->{id};

	my $artist = join( ', ', map { $_->{title} } @{ $track->{artists} || [] } );
	my $image  = $track->{release}{image}{src} if $track->{release};

	return {
		name     => $track->{title},
		artist   => $artist,
		duration => $track->{duration},
		url      => 'zvuk://track/' . $track->{id},
		image    => $image,
		type     => 'audio',
	};
}

sub releaseToItem {
	my ( $release ) = @_;
	return unless $release && ref $release eq 'HASH' && $release->{id};

	my $artist = join( ', ', map { $_->{title} } @{ $release->{artists} || [] } );

	return {
		name  => $release->{title},
		artist=> $artist,
		url   => 'zvuk://release/' . $release->{id},
		image => $release->{image}{src},
		type  => 'link',
	};
}

sub artistToItem {
	my ( $artist ) = @_;
	return unless $artist && ref $artist eq 'HASH' && $artist->{id};

	return {
		name  => $artist->{title},
		url   => 'zvuk://artist/' . $artist->{id},
		image => $artist->{image}{src},
		type  => 'link',
	};
}

sub playlistToItem {
	my ( $playlist ) = @_;
	return unless $playlist && ref $playlist eq 'HASH' && $playlist->{id};

	return {
		name  => $playlist->{title},
		url   => Plugins::Zvuk::Browse::feedUrl( { menu => 'playlist', id => $playlist->{id} } ),
		image => $playlist->{image}{src},
		type  => 'playlist',
	};
}

1;
