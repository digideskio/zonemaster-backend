package Zonemaster::WebBackend::Runner;
our $VERSION = '1.0.5';

use strict;
use warnings;
use 5.14.2;

use DBI qw(:utils);
use JSON;

use Net::LDNS;

use Zonemaster;
use Zonemaster::Translator;
use Zonemaster::WebBackend::Config;

sub new {
    my ( $class, $params ) = @_;
    my $self = {};

    if ( $params && $params->{db} ) {
        eval "require $params->{db}";
        $self->{db} = "$params->{db}"->new();
    }
    else {
        my $backend_module = "Zonemaster::WebBackend::DB::" . Zonemaster::WebBackend::Config->BackendDBType();
        eval "require $backend_module";
        $self->{db} = $backend_module->new();
    }

    bless( $self, $class );
    return $self;
}

sub run {
    my ( $self, $test_id ) = @_;
    my @accumulator;
    my %counter;
    my %counter_for_progress_indicator;

    my $params;

    my $progress = $self->{db}->test_progress( $test_id, 1 );

    $params = $self->{db}->get_test_params( $test_id );

    my %methods = Zonemaster->all_methods;

    foreach my $module ( keys %methods ) {
        foreach my $method ( @{ $methods{$module} } ) {
            $counter_for_progress_indicator{planned}{ $module . '::' . $method } = $module . '::';
        }
    }

    my ( $domain ) = $params->{domain};
    if ( !$domain ) {
        die "Must give the name of a domain to test.\n";
    }
    $domain = $self->to_idn( $domain );

    Zonemaster->config->get->{net}{ipv4} = ( $params->{ipv4} ) ? ( 1 ) : ( 0 );
    Zonemaster->config->get->{net}{ipv6} = ( $params->{ipv6} ) ? ( 1 ) : ( 0 );

    # used for progress indicator
    my ( $previous_module, $previous_method ) = ( '', '' );

    # Callback defined here so it closes over the setup above.
    Zonemaster->logger->callback(
        sub {
            my ( $entry ) = @_;

            foreach my $trace ( reverse @{ $entry->trace } ) {
                foreach my $module_method ( keys %{ $counter_for_progress_indicator{planned} } ) {
                    if ( index( $trace->[1], $module_method ) > -1 ) {
                        my $percent_progress = 0;
                        my ( $module ) = ( $module_method =~ /(.+::)[^:]+/ );
                        if ( $previous_module eq $module ) {
                            $counter_for_progress_indicator{executed}{$module_method}++;
                        }
                        elsif ( $previous_module ) {
                            foreach my $planned_module_method ( keys %{ $counter_for_progress_indicator{planned} } ) {
                                $counter_for_progress_indicator{executed}{$planned_module_method}++
                                  if ( $counter_for_progress_indicator{planned}{$planned_module_method} eq
                                    $previous_module );
                            }
                        }
                        $previous_module = $module;

                        if ( $previous_method ne $module_method ) {
                            $percent_progress = sprintf(
                                "%.0f",
                                100 * (
                                    scalar( keys %{ $counter_for_progress_indicator{executed} } ) /
                                      scalar( keys %{ $counter_for_progress_indicator{planned} } )
                                )
                            );
                            $self->{db}->test_progress( $test_id, $percent_progress );

                            $previous_method = $module_method;
                        }
                    }
                }
            }

            $counter{ uc $entry->level } += 1;
        }
    );

    if ( $params->{nameservers} && @{ $params->{nameservers} } > 0 ) {
        $self->add_fake_delegation( $domain, $params->{nameservers} );
    }

    if ( $params->{ds_info} && @{ $params->{ds_info} } > 0 ) {
        $self->add_fake_ds( $domain, $params->{ds_info} );
    }
    
    if ( $params->{profile} eq 'test_profile_1' ) {
		if (Zonemaster::WebBackend::Config->CustomProfilesPath()) {
			Zonemaster->config->load_policy_file( Zonemaster::WebBackend::Config->CustomProfilesPath() . '/iana-profile.json' );
		}
		else {
			Zonemaster->config->load_policy_file( 'iana-profile.json' );
		}
	}

    # Actually run tests!
    eval { Zonemaster->test_zone( $domain ); };
    if ( $@ ) {
        my $err = $@;
        if ( blessed $err and $err->isa( "NormalExit" ) ) {
            say STDERR "Exited early: " . $err->message;
        }
        else {
            die $err;    # Don't know what it is, rethrow
        }
    }

    $self->{db}->test_results( $test_id, Zonemaster->logger->json( 'INFO' ) );

    $progress = $self->{db}->test_progress( $test_id );

    return;
} ## end sub run

sub add_fake_delegation {
    my ( $self, $domain, $nameservers ) = @_;
    my %data;

    foreach my $ns_ip_pair ( @$nameservers ) {
        push( @{ $data{ $self->to_idn( $ns_ip_pair->{ns} ) } }, $ns_ip_pair->{ip} )
          if ( $ns_ip_pair->{ns} && $ns_ip_pair->{ip} );
    }

    Zonemaster->add_fake_delegation( $domain => \%data );

    return;
}

sub add_fake_ds {
    my ( $self, $domain, $ds_info ) = @_;
    my @data;

    foreach my $ds ( @{ $ds_info } ) {
        push @data, { keytag => $ds->{keytag}, algorithm => $ds->{algorithm}, type => $ds->{digtype}, digest => $ds->{digest} };
    }

    Zonemaster->add_fake_ds( $domain => \@data );

    return;
}

sub to_idn {
    my ( $self, $str ) = @_;

    if ( $str =~ m/^[[:ascii:]]+$/ ) {
        return $str;
    }

    if ( Net::LDNS::has_idn() ) {
        return Net::LDNS::to_idn( $str );
    }
    else {
        warn __( "Warning: Net::LDNS not compiled with libidn, cannot handle non-ASCII names correctly." );
        return $str;
    }
}

1;
