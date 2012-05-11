#!/usr/bin/perl
use strict;

sub populator_etv120229 {
    my $data = $_[0];
    my @y = qw();
    foreach (@{$data->{body}->{div}->{h3}}) {
        my $yi = {};
        $yi->{'t0'} = $_->{span}->{content};
        $yi->{'label'} = $_->{a}->{content};
        $yi->{'url'} = $_->{a}->{href};
        $yi->{'description'} = '';
        push @y, $yi;
    }
    return @y;
}

1;