package Mail::Milter::Authentication::Handler::SMIME;
use strict;
use warnings;
use base 'Mail::Milter::Authentication::Handler';
use version; our $VERSION = version->declare('v1.0.2');

use English qw{ -no_match_vars };
use Sys::Syslog qw{:standard :macros};

use Convert::X509;
use Crypt::SMIME;
use Email::MIME;

sub default_config {
    return {
        'hide_none' => 0,
        'pki_store' => '/etc/ssl/certs',
   };
}

sub envfrom_callback {
    my ($self) = @_;
    $self->{'data'}  = [];
    $self->{'found'} = 0;
    $self->{'added'} = 0;
    return;
}

sub header_callback {
    my ( $self, $header, $value ) = @_;
    push @{$self->{'data'}} , $header . ': ' . $value . "\r\n";
    return;
}

sub eoh_callback {
    my ( $self ) = @_;
    push @{$self->{'data'}} , "\r\n";
    return;
}

sub body_callback {
    my ( $self, $chunk ) = @_;
    push @{$self->{'data'}} , $chunk;
    return;
}

sub eom_callback {
    my ( $self ) = @_;

    my $config = $self->handler_config();

    my $data = join( q{}, @{ $self->{'data'} } );

    eval {
        my $parsed = Email::MIME->new( $data );
        $self->_parse_mime( $parsed );

        if ( $self->{'found'} == 0 ) {
            if ( !( $config->{'hide_none'} ) ) {
                $self->add_auth_header(
                    $self->format_header_entry( 'smime', 'none' ),
                );
            }
        }
        elsif ( $self->{'added'} == 0 ) {
            $self->add_auth_header(
                $self->format_header_entry( 'smime', 'temperror' ),
            );
        }
    };
    if ( my $error = $@ ) {
        $self->log_error( 'SMIME Execution Error ' . $error );
        $self->add_auth_header(
            $self->format_header_entry( 'smime', 'temperror' ),
        );
    }

    return;
}


sub _parse_mime {
    my ( $self, $mime ) = @_;

    my $content_type = $mime->content_type();
    $content_type =~ s/;.*//;

    if ( $content_type eq 'multipart/signed' ) {
        my $header = $mime->{'header'}->as_string();
        my $body   = $mime->body_raw();
        $self->_check_mime( $header . "\r\n" . $body );
    }

    if ( $content_type eq 'application/pkcs7-mime' ) {
        # See rfc5751 3.4
        my $header = $mime->{'header'}->as_string();
        my $body   = $mime->body_raw();
        $self->_check_mime( $header . "\r\n" . $body );
    }

    my @parts = $mime->subparts();

    foreach my $part ( @parts ) {
        $self->_parse_mime( $part );
    }

}

sub close_callback {
    my ( $self ) = @_;
    delete $self->{'added'};
    delete $self->{'found'};
    delete $self->{'data'};
    return;
}

sub _check_mime {
    my ( $self, $data ) = @_;

    $self->{'found'} = 1;

    my $smime = Crypt::SMIME->new();
    my $config = $self->handler_config();
    $smime->setPublicKeyStore( $config->{'pki_store'} );

    my $is_signed;
    $is_signed = eval{ $smime->isSigned( $data ); };
    if ( my $error = $@ ) {
        $self->log_error( 'SMIME isSigned Error ' . $error );
    }

    if ( $is_signed ) {

        my $source;
        eval {
            $source = $smime->check( $data );
        };
        if ( my $error = $@ ) {
            $self->log_error( 'SMIME check Error ' . $error );
            $self->add_auth_header(
                $self->format_header_entry( 'smime', 'fail' ),
            );
            $self->{'added'} = 1;
            ## ToDo extract the reason for failure and add as header comment
        }
        else {
            my $signatures = Crypt::SMIME::getSigners( $data );
            my $all_certs  = Crypt::SMIME::extractCertificates( $data );
            $self->_decode_certs( $signatures, $all_certs );
        }
    }

}

sub _decode_certs {
    my ( $self, $signatures, $all_certs ) = @_;

    my $seen = {};


    SIGNATURE:
    foreach my $cert ( @{$signatures} ) {


        my $cert_info = Convert::X509::Certificate->new( $cert );

        my $subject = $cert_info->subject();
        my $issuer  = $cert_info->issuer();
        my $from    = $cert_info->from();
        my $to      = $cert_info->to();
        my $eku     = $cert_info->eku();
        my $serial  = $cert_info->serial();
        my @aia     = $cert_info->aia();

        next SIGNATURE if $seen->{ $serial };
        $seen->{ $serial } = 1;

        my @results;
        ## ToDo identify part
        ##$data->{ 'body.smime-part' }       = ???;
        push @results, $self->format_header_entry( 'body.smime-identifier', $subject->{'E'}[0] )
            . '(' . $self->format_header_comment( $subject->{'CN'}[0] ) . ')';
        push @results, $self->format_header_entry( 'body.smime-serial', $serial );
        my $issuer_text = join( ',', map{ $_ . '=' . $issuer->{$_}[0] } sort keys (%{$issuer}) );
        $issuer_text =~ s/\"/ /g;
        push @results, 'body.smime-issuer="' . $self->format_ctext( $issuer_text ) . '"' ;
        push @results, 'x-smime-valid-from="' . $self->format_ctext( $from ) . '"';
        push @results, 'x-smime-valid-to="'   . $self->format_ctext( $to ) . '"';
        $self->add_auth_header(
            join( "\n        ",
                $self->format_header_entry( 'smime', 'pass' ),
                @results,
            )
        );
        $self->{'added'} = 1;
    }

    # Non standard
    CERT:
    foreach my $cert ( @{$all_certs} ) {

        my $cert_info = Convert::X509::Certificate->new( $cert );

        my $subject = $cert_info->subject();
        my $issuer  = $cert_info->issuer();
        my $from    = $cert_info->from();
        my $to      = $cert_info->to();
        my $eku     = $cert_info->eku();
        my $serial  = $cert_info->serial();
        my @aia     = $cert_info->aia();

        next CERT if $seen->{ $serial };
        $seen->{ $serial } = 1;

        my @results;
        ## ToDo identify part
        #$data->{ 'smime-part' }       = ???;
        push @results, $self->format_header_entry( 'x-smime-chain-identifier', ( $subject->{'E'}[0] || 'null' ) )
            . ' (' . $self->format_header_comment( $subject->{'CN'}[0] ) . ')';
        push @results, $self->format_header_entry( 'x-smime-chain-serial', $serial );
        my $issuer_text = join( ',', map{ $_ . '=' . $issuer->{$_}[0] } sort keys (%{$issuer}) );
        $issuer_text =~ s/\"/ /g;
        push @results, 'x-smime-chain-issuer="' . $self->format_ctext( $issuer_text ) . '"' ;
        push @results, 'x-smime-chain-valid-from="' . $self->format_ctext( $from ) . '"';
        push @results, 'x-smime-chain-valid-to="'   . $self->format_ctext( $to ) . '"';
        #        $self->add_auth_header(
        #            join( "\n        ",
        #                $self->format_header_entry( 'x-smime-chain', 'pass' ),
        #                @results,
        #            )
        #        );
        #        $self->{'added'} = 1;
    }

    return;
}

1;
