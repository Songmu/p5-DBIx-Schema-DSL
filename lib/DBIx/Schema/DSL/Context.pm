package DBIx::Schema::DSL::Context;
use 5.008_001;
use strict;
use warnings;

use Moo;
use SQL::Translator;

has name => (
    is  => 'rw',
);

has db => (
    is  => 'rw',
    default => sub {'MySQL'},
);

has translator => (
    is  => 'lazy',
    default => sub {
        SQL::Translator->new;
    },
);

has schema => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        $self->translator->schema->name($self->name);
        $self->translator->schema->database($self->db);
        $self->translator->schema;
    },
);

has _creating_table => (
    is => 'rw',
    clearer => '_clear_creating_table',
);

has translate => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $output = $self->translator->translate(to => $self->db);
        # ignore initial comments.
        1 while $output =~ s/\A--.*?\r?\n//ms;
        $output;
    },
);

has table_extra => (
    is => 'lazy',
    default => sub {
        shift->db eq 'MySQL' ? {
            mysql_table_type => 'InnoDB',
            mysql_charset    => 'utf8',
        } : {};
    },
);

no Moo;

sub _creating_table_name {
    shift->_creating_table->{table_name}
        or die 'Not in create_table block.';
}

1;
