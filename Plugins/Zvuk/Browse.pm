package Plugins::Zvuk::Browse;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring string);

use Plugins::Zvuk::API;
use Plugins::Zvuk::API::Async;

my $log   = logger('plugin.zvuk');
my $prefs = preferences('plugin.zvuk');

sub feedUrl {
	my ($params) = @_;
	return sub {
		my ( $client, $cb, $args, @passthrough ) = @_;
		handleFeed( $client, $cb, $args, @passthrough, { params => $params } );
	};
}

sub _mergeParams {
	my ( $args, @extra ) = @_;

	my $params = { %{ $args->{params} || {} } };

	for my $chunk (@extra) {
		if ( ref $chunk eq 'HASH' ) {
			if ( $chunk->{params} ) {
				%$params = ( %$params, %{ $chunk->{params} } );
			}
			else {
				%$params = ( %$params, %$chunk );
			}
		}
	}

	if ( defined $args->{search} ) {
		$params->{search} = $args->{search};
	}

	return $params;
}

sub handleFeed {
	my ( $client, $cb, $args, @passthrough ) = @_;

	unless ( Plugins::Zvuk::API::getToken() ) {
		return $cb->( {
			items => [ {
				name => cstring( $client, 'PLUGIN_ZVUK_REQUIRES_TOKEN' ),
				type => 'textarea',
			} ],
		} );
	}

	my $params = _mergeParams( $args || {}, @passthrough );
	my $menu   = $params->{menu} || 'root';
	my $search = $params->{search};

	if ( defined $search && length $search ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Search: $search");
		return Plugins::Zvuk::API::Async::search( $client, $cb, $search );
	}

	if ( $menu eq 'playlist' && $params->{id} ) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Playlist: $params->{id}");
		return Plugins::Zvuk::API::Async::getPlaylistTracks( $client, $cb, $params->{id} );
	}

	if ( $menu eq 'playlists' ) {
		return Plugins::Zvuk::API::Async::getUserPlaylists( $client, $cb );
	}

	if ( $menu eq 'favorites' ) {
		return Plugins::Zvuk::API::Async::getFavoriteTracks( $client, $cb );
	}

	if ( $menu eq 'albums' ) {
		return $cb->( {
			items => [ {
				name => cstring( $client, 'PLUGIN_ZVUK_SEARCH' ),
				type => 'search',
				url  => \&handleFeed,
			} ],
		} );
	}

	my $feed = \&handleFeed;

	$cb->( {
		items => [
			{
				name => cstring( $client, 'PLUGIN_ZVUK_SEARCH' ),
				type => 'search',
				url  => $feed,
			},
			{
				name        => cstring( $client, 'PLUGIN_ZVUK_PLAYLISTS' ),
				type        => 'link',
				url         => $feed,
				passthrough => [ { menu => 'playlists' } ],
			},
			{
				name        => cstring( $client, 'PLUGIN_ZVUK_ALBUMS' ),
				type        => 'link',
				url         => $feed,
				passthrough => [ { menu => 'albums' } ],
			},
			{
				name        => cstring( $client, 'PLUGIN_ZVUK_FAVORITES' ),
				type        => 'link',
				url         => $feed,
				passthrough => [ { menu => 'favorites' } ],
			},
		],
	} );
}

1;
