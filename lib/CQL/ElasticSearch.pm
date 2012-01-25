package CQL::ElasticSearch; # TODO deal with multiple terms for ops other than any, all, exact!!!

use Catmandu::Sane;
use Catmandu::Util qw(load_package);
use CQL::Parser;
use Moo;

has mapping => (is => 'ro');

my $any_field = qr'^(srw|cql)\.(serverChoice|anywhere)$'i;
my $match_all = qr'^(srw|cql)\.allRecords$'i;
my $distance_modifier = qr'\s*\/\s*distance\s*<\s*(\d+)'i;

my $parser;

sub parse {
    my ($self, $query) = @_;
    $parser ||= CQL::Parser->new;
    $self->visit($parser->parse($query));
}

sub visit {
    my ($self, $node) = @_;

    if ($node->isa('CQL::TermNode')) {
        my $term = $node->getTerm;

        if ($term =~ $match_all) {
            return { match_all => {} };
        }

        my $qualifier = $node->getQualifier;
        my $relation  = $node->getRelation;
        my @modifiers = $relation->getModifiers;
        my $base      = lc $relation->getBase;

        if ($base eq 'scr') {
            $base = '=';
        }

        if ($qualifier =~ $any_field) {
            $qualifier = '_all';
        }

        if ($self->mapping) {
            if (my $mapping = $self->mapping->{$qualifier}) {
                $mapping->{op}{$base} or die "operator $base not allowed";
                my $op = $mapping->{op}{$base};
                if (ref $op && $op->{field}) {
                    $qualifier = $op->{field};
                } elsif ($mapping->{field}) {
                    $qualifier = $mapping->{field};
                }
                my $cb;
                if (ref $op && $op->{cb}) {
                    my ($pkg, $sub) = @{$op->{cb}};
                    $term = load_package($pkg)->$sub($term);
                } elsif ($mapping->{cb}) {
                    my ($pkg, $sub) = @{$mapping->{cb}};
                    $term = load_package($pkg)->$sub($term);
                }
            } else {
                die "field $qualifier not allowed";
            }
        }

        if ($base eq '=') {
            if (ref $qualifier) {
                return { bool => { should => [ map {
                    my $q = $_;
                    if (ref $term) {
                        map { _text_node($q, $_, @modifiers) } @$term;
                    } else {
                        _text_node($q, $term, @modifiers);
                    }
                } @$qualifier ] } };
            } else {
                if (ref $term) {
                    return { bool => { should => [ map { _text_node($qualifier, $_, @modifiers) } @$term ] } };
                } else {
                    return _text_node($qualifier, $term, @modifiers);
                }
            }
        } elsif ($base eq '<') {
            if (ref $qualifier) {
                return { bool => { should => [ map { { range => { $_ => { lt => $term } } } } @$qualifier ] } };
            } else {
                return { range => { $qualifier => { lt => $term } } };
            }
        } elsif ($base eq '>') {
            if (ref $qualifier) {
                return { bool => { should => [ map { { range => { $_ => { gt => $term } } } } @$qualifier ] } };
            } else {
                return { range => { $qualifier => { gt => $term } } };
            }
        } elsif ($base eq '<=') {
            if (ref $qualifier) {
                return { bool => { should => [ map { { range => { $_ => { lte => $term } } } } @$qualifier ] } };
            } else {
                return { range => { $qualifier => { lte => $term } } };
            }
        } elsif ($base eq '>=') {
            if (ref $qualifier) {
                return { bool => { should => [ map { { range => { $_ => { gte => $term } } } } @$qualifier ] } };
            } else {
                return { range => { $qualifier => { gte => $term } } };
            }
        } elsif ($base eq '<>') {
            if (ref $qualifier) {
                return { bool => { must_not => [ map {
                    my $q = $_;
                    if (ref $term) {
                        map { { text_phrase => { $q => { query => $_ } } } } @$term;
                    } else {
                        { text_phrase => { $q => { query => $term } } };
                    }
                } @$qualifier ] } };
            } else {
                if (ref $term) {
                    return { bool => { must_not => [ map { { text_phrase => { $qualifier => { query => $_ } } } } @$term ] } };
                } else {
                    return { bool => { must_not => [ { text_phrase => { $qualifier => { query => $term } } } ] } };
                }
            }
        } elsif ($base eq 'exact') {
            if (ref $qualifier) {
                return { bool => { should => [ map {
                    my $q = $_;
                    if (ref $term) {
                        map { { text_phrase => { $q => { query => $_ } } } } @$term;
                    } else {
                        { text_phrase => { $q => { query => $term } } };
                    }
                } @$qualifier ] } };
            } else {
                if (ref $term) {
                    return { bool => { should => [map { { text_phrase => { $qualifier => { query => $_ } } } } @$term] } };
                } else {
                    return { text_phrase => { $qualifier => { query => $term } } };
                }
            }
        } elsif ($base eq 'any') {
            if (ref $qualifier) {
                if (ref $term) {
                    return { bool => { should => [ map {
                        my $q = $_;
                        if (ref $term) {
                            map { { text => { $q => { query => $_ } } } } @$term;
                        } else {
                            { text => { $q => { query => $term } } };
                        }
                    } @$qualifier ] } };
                } else {
                    return { bool => { should => [ map { { text => { $_ => { query => $term } } } } @$qualifier ] } };
                }
            } else {
                if (ref $term) {
                    return { bool => { should => [map { { text => { $qualifier => { query => $_ } } } } @$term] } };
                } else {
                    return { text => { $qualifier => { query => $term } } };
                }
            }
        } elsif ($base eq 'all') {
            if (ref $qualifier) {
                return { bool => { should => [ map {
                    my $q = $_;
                    if (ref $term) {
                        map { { text => { $q => { query => $_, operator => 'and' } } } } @$term;
                    } else {
                        { text => { $q => { query => $term, operator => 'and' } } };
                    }
                } @$qualifier ] } };
            } else {
                if (ref $term) {
                    return { bool => { should => [map { { text => { $qualifier => { query => $_, operator => 'and' } } } } @$term] } };
                } else {
                    return { text => { $qualifier => { query => $term, operator => 'and' } } };
                }
            }
        } elsif ($base eq 'within') {
            my @range = split /\s+/, $term;
            if (@range == 1) {
                if (ref $qualifier) {
                    return { bool => { should => [ map { { text => { $_ => { query => $term } } } } @$qualifier ] } };
                } else {
                    return { text => { $qualifier => { query => $term } } };
                }
            }
            if (ref $qualifier) {
                return { bool => { should => [ map { { range => { $_ => { lte => $range[0], gte => $range[1] } } } } @$qualifier ] } };
            } else {
                return { range => { $qualifier => { lte => $range[0], gte => $range[1] } } };
            }
        }

        if (ref $qualifier) {
            return { bool => { should => [ map {
                my $q = $_;
                if (ref $term) {
                    map { _text_node($q, $_, @modifiers) } @$term;
                } else {
                    _text_node($q, $term, @modifiers);
                }
            } @$qualifier ] } };
        } else {
            if (ref $term) {
                return { bool => { should => [ map { _text_node($qualifier, $_, @modifiers) } @$term ] } };
            } else {
                return _text_node($qualifier, $term, @modifiers);
            }
        }
    }

    if ($node->isa('CQL::ProxNode')) { # TODO mapping
        my $slop = 0;
        my $qualifier = $node->left->getQualifier;
        my $term = join ' ', $node->left->getTerm, $node->right->getTerm;
        if (my ($n) = $node->op =~ $distance_modifier) {
            $slop = $n - 1 if $n > 1;
        }
        if ($qualifier =~ $any_field) {
            $qualifier = '_all';
        }

        return { text_phrase => { $qualifier => { query => $term, slop => $slop } } };
    }

    if ($node->isa('CQL::BooleanNode')) {
        my $op = lc $node->op;
        my $bool;
        if ($op eq 'and') { $bool = 'must' }
        elsif ($op eq 'or') { $bool = 'should' }
        else { $bool = 'must_not' }

        return { bool => { $bool => [
            $self->visit($node->left),
            $self->visit($node->right)
        ] } };
    }
}

sub _text_node {
    my ($qualifier, $term, @modifiers) = @_;
    if ($term =~ /^\^./) { # TODO mapping
        return { text_phrase_prefix => { $qualifier => { query => substr($term, 1), max_expansions => 10 } } };
    } elsif ($term =~ /[^\\][*?]/) { # TODO mapping
        return { wildcard => { $qualifier => $term } };
    }
    for my $m (@modifiers) {
        if ($m->[1] eq 'fuzzy') { # TODO mapping
            return { text_phrase => { $qualifier => { query => $term, fuzziness => 0.5 } } };
        }
    }
    { text_phrase => { $qualifier => { query => $term } } };
}

1;

=head1 NAME

CQL::ElasticSearch - Converts a CQL query string to a ElasticSearch query hashref

=head1 SYNOPSIS

    $es_query_hashref = CQL::ElasticSearch->parse($cql_query_string);

=head1 DESCRIPTION

This package currently parses most of CQL 1.1:

    and
    or
    not
    prox
    prox/distance<$n
    srw.allRecords
    srw.serverChoice
    srw.anywhere
    cql.allRecords
    cql.serverChoice
    cql.anywhere
    =
    scr
    =/fuzzy
    scr/fuzzy
    <
    >
    <=
    >=
    <>
    exact
    all
    any
    within

=head1 METHODS

=head2 parse

Parses the given CQL query string with L<CQL::Parser> and converts it to a ElasticSearch query hashref.

=head2 visit

Converts the given L<CQL::Node> to a ElasticSearch query hashref.

=head1 TODO

support cql 1.2, more modifiers (esp. all of masked), sortBy, encloses

=head1 SEE ALSO

L<CQL::Parser>.

=cut

