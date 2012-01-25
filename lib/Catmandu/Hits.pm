package Catmandu::Hits;

use Catmandu::Sane;
use Role::Tiny ();
use Role::Tiny::With;

with 'Catmandu::Iterable';

sub new {
    bless $_[1], $_[0];
}

sub total {
    $_[0]->{total};
}

sub start {
    $_[0]->{start};
}

sub limit {
    $_[0]->{limit};
}

sub size {
    scalar @{ $_[0]->{hits} };
}

sub hits {
    $_[0]->{hits};
}

sub to_array { goto &hits }

sub count { goto &size }

sub generator {
    my ($self) = @_;
    my $hits = $self->hits;
    my $i = 0;
    sub {
        $hits->[$i++];
    };
}

sub each {
    my ($self, $sub) = @_;
    my $hits = $self->hits;
    for my $hit (@$hits) {
        $sub->($hit);
    }
    $self->size;
}

1;

=head1 NAME

Catmandu::Hits - Iterable object that wraps L<Catmandu::Index> search hits

=head1 SYNOPSIS

    my $hits = $index->search("foo")
    $hits->each(sub {
        say $_[0]->{bar};
    });
    $hits->hits
    => [{bar => 'baz'}, ...]
    $hits->total
    => 10043

=head1 DESCRIPTION

Instances are normally created by a L<Catmandu::Index>.

=head1 METHODS

=head2 total

=head2 start

=head2 limit

=head2 size

=head2 hits

=head2 each

Passes each hit in turn to the subref and returns the number of hits passed

    my $n = $hits->each(sub {
        my $hashref = $_[0];
    });

=head1 SEE ALSO

L<Catmandu::Index>.

=cut