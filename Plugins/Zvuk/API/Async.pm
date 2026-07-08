package Plugins::Zvuk::API::Async;

use strict;
use warnings;

use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);

use Plugins::Zvuk::API;

my $log = logger('plugin.zvuk');

sub _graphqlAsync {
	my ( $query, $operationName, $variables, $cb, $errCb ) = @_;

	my @headers = Plugins::Zvuk::API::_requestHeaders();
	return $errCb->() unless @headers;

	my $payload = encode_json( {
		query         => $query,
		operationName => $operationName,
		variables     => $variables || {},
	} );

	my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;
			my $data = Plugins::Zvuk::API::_decodeJson( ${ $response->contentRef } );

			if ( !$data || Plugins::Zvuk::API::_apiError( $data, $operationName ) ) {
				return $errCb->();
			}

			$cb->( $data->{data} );
		},
		sub {
			$log->warn("Async GraphQL $operationName failed: $_[1]");
			$errCb->();
		},
	);

	$http->post(
		Plugins::Zvuk::API::BASE_URL . '/api/v1/graphql',
		@headers,
		$payload,
	);
}

sub search {
	my ( $client, $cb, $query ) = @_;

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

	_graphqlAsync(
		$gql, 'search', { query => $query, limit => 20 },
		sub {
			my $data = shift;
			my @items;

			if ( my $tracks = $data->{search}{tracks}{items} ) {
				for my $track ( @$tracks ) {
					push @items, Plugins::Zvuk::API::trackToItem($track);
				}
			}

			if ( my $artists = $data->{search}{artists}{items} ) {
				for my $artist ( @$artists ) {
					push @items, Plugins::Zvuk::API::artistToItem($artist);
				}
			}

			if ( my $releases = $data->{search}{releases}{items} ) {
				for my $release ( @$releases ) {
					push @items, Plugins::Zvuk::API::releaseToItem($release);
				}
			}

			if ( !@items ) {
				push @items, {
					name => string('PLUGIN_ZVUK_NO_RESULTS'),
					type => 'textarea',
				};
			}

			$cb->( { items => \@items } );
		},
		sub {
			$cb->( { items => [ {
				name => string('PLUGIN_ZVUK_API_ERROR'),
				type => 'textarea',
			} ] } );
		},
	);
}

sub getUserPlaylists {
	my ( $client, $cb ) = @_;

	my $gql = <<'GQL';
query userPlaylists {
	collection {
		playlists { id }
	}
}
GQL

	_graphqlAsync(
		$gql, 'userPlaylists', {},
		sub {
			my $data = shift;
			my $playlists = $data->{collection}{playlists} || [];
			my @ids = map { $_->{id} } @$playlists;

			if ( !@ids ) {
				return $cb->( { items => [ {
					name => string('PLUGIN_ZVUK_NO_RESULTS'),
					type => 'textarea',
				} ] } );
			}

			my $detailGql = <<'GQL';
query getPlaylists($ids: [ID!]!) {
	getPlaylists(ids: $ids) {
		id title duration
		image { src }
	}
}
GQL

			_graphqlAsync(
				$detailGql, 'getPlaylists', { ids => \@ids },
				sub {
					my $detail = shift;
					my @items = map {
						Plugins::Zvuk::API::playlistToItem($_)
					} @{ $detail->{getPlaylists} || [] };

					$cb->( { items => \@items } );
				},
				sub {
					$cb->( { items => [ {
						name => string('PLUGIN_ZVUK_API_ERROR'),
						type => 'textarea',
					} ] } );
				},
			);
		},
		sub {
			$cb->( { items => [ {
				name => string('PLUGIN_ZVUK_API_ERROR'),
				type => 'textarea',
			} ] } );
		},
	);
}

sub getPlaylistTracks {
	my ( $client, $cb, $playlistId ) = @_;

	my $gql = <<'GQL';
query getPlaylistTracks($id: ID!, $limit: Int = 100, $offset: Int = 0) {
	playlistTracks(id: $id, limit: $limit, offset: $offset) {
		id title duration
		artists { id title }
		release { id title image { src } }
	}
}
GQL

	_graphqlAsync(
		$gql, 'getPlaylistTracks', {
			id     => "$playlistId",
			limit  => 100,
			offset => 0,
		},
		sub {
			my $data = shift;
			my @items = map {
				Plugins::Zvuk::API::trackToItem($_)
			} @{ $data->{playlistTracks} || [] };

			if ( !@items ) {
				push @items, {
					name => string('PLUGIN_ZVUK_NO_RESULTS'),
					type => 'textarea',
				};
			}

			$cb->( { items => \@items } );
		},
		sub {
			$cb->( { items => [ {
				name => string('PLUGIN_ZVUK_API_ERROR'),
				type => 'textarea',
			} ] } );
		},
	);
}

sub getFavoriteTracks {
	my ( $client, $cb ) = @_;

	my $gql = <<'GQL';
query userTracks($orderBy: TrackOrderByType, $orderDirection: OrderDirectionType) {
	collection {
		tracks(orderBy: $orderBy, orderDirection: $orderDirection) {
			id
		}
	}
}
GQL

	_graphqlAsync(
		$gql, 'userTracks', {
			orderBy        => 'dateAdded',
			orderDirection => 'desc',
		},
		sub {
			my $data = shift;
			my @ids = map { $_->{id} } @{ $data->{collection}{tracks} || [] };

			if ( !@ids ) {
				return $cb->( { items => [ {
					name => string('PLUGIN_ZVUK_NO_RESULTS'),
					type => 'textarea',
				} ] } );
			}

			my $tracksGql = <<'GQL';
query getTracks($ids: [ID!]!) {
	getTracks(ids: $ids) {
		id title duration
		artists { id title }
		release { id title image { src } }
	}
}
GQL

			_graphqlAsync(
				$tracksGql, 'getTracks', { ids => \@ids },
				sub {
					my $tracks = shift;
					my @items = map {
						Plugins::Zvuk::API::trackToItem($_)
					} @{ $tracks->{getTracks} || [] };

					$cb->( { items => \@items } );
				},
				sub {
					$cb->( { items => [ {
						name => string('PLUGIN_ZVUK_API_ERROR'),
						type => 'textarea',
					} ] } );
				},
			);
		},
		sub {
			$cb->( { items => [ {
				name => string('PLUGIN_ZVUK_API_ERROR'),
				type => 'textarea',
			} ] } );
		},
	);
}

1;
