package Database::Migrator::mysql;

use strict;
use warnings;
use namespace::autoclean;

use Database::Migrator::Types qw( Str );
use DBD::mysql;
use DBI;
use File::Slurp qw( read_file );
use IPC::Run3 qw( run3 );

use Moose;

with 'Database::Migrator::Core';

has character_set => (
    is        => 'ro',
    isa       => Str,
    predicate => '_has_character_set',
);

has collation => (
    is        => 'ro',
    isa       => Str,
    predicate => '_has_collation',
);

sub _build_database_exists {
    my $self = shift;

    my $databases;
    run3(
        [ $self->_cli_args(), '-e', 'SHOW DATABASES' ],
        \undef,
        \$databases,
        \undef,
    );

    my $database = $self->database();

    return $databases =~ /\Q$database\E/;
}

sub _create_database {
    my $self = shift;

    my $database = $self->database();

    $self->logger()->info("Creating the $database database");

    my $create_ddl = "CREATE DATABASE $database";
    $create_ddl .= ' CHARACTER SET = ' . $self->character_set()
        if $self->_has_character_set();
    $create_ddl .= ' COLLATE = ' . $self->collation()
        if $self->_has_collation();

    $self->_run_command(
        [ $self->_cli_args(), qw(  --batch -e ), $create_ddl ] );

    return;
}

sub _run_ddl {
    my $self = shift;
    my $file = shift;

    my $ddl = read_file( $file->stringify() );

    $self->_run_command(
        [ $self->_cli_args(), '--database', $self->database(), '--batch' ],
        $ddl,
    );
}

sub _cli_args {
    my $self = shift;

    my @cli = 'mysql';
    push @cli, '-u' . $self->username() if defined $self->username();
    push @cli, '-p' . $self->password() if defined $self->password();
    push @cli, '-h' . $self->host()     if defined $self->host();
    push @cli, '-P' . $self->port()     if defined $self->port();

    return @cli;
}

sub _run_command {
    my $self    = shift;
    my $command = shift;
    my $input   = shift;

    my $stdout = q{};
    my $stderr = q{};

    my $handle_stdout = sub {
        $self->logger()->debug(@_);

        $stdout .= $_ for @_;
    };

    my $handle_stderr = sub {
        $self->logger()->debug(@_);

        $stderr .= $_ for @_;
    };

    $self->logger()->debug("Running command: [@{$command}]");

    return if $self->dry_run();

    run3( $command, \$input, $handle_stdout, $handle_stderr );

    if ($?) {
        my $exit = $? >> 8;

        my $msg = "@{$command} returned an exit code of $exit\n";
        $msg .= "\nSTDOUT:\n$stdout\n\n" if length $stdout;
        $msg .= "\nSTDERR:\n$stderr\n\n" if length $stderr;

        die $msg;
    }

    return $stdout;
}

__PACKAGE__->meta()->make_immutable();

1;

#ABSTRACT: Database::Migrator implementation for MySQL

=head1 SYNOPSIS

  package MyApp::Migrator;

  use Moose;

  extends 'Database::Migrator::mysql';

  has '+database' => (
      required => 0,
      default  => 'MyApp',
  );

=head1 DESCRIPTION

This module provides a L<Database::Migrator> implementation for MySQL. See
L<Database::Migrator> and L<Database::Migrator::Core> for more documentation.
