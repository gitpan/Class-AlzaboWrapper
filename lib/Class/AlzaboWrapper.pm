package Class::AlzaboWrapper;

use strict;

use vars qw($VERSION);

$VERSION = 0.05;

use Class::AlzaboWrapper::Cursor;

use Exception::Class ( 'Class::AlzaboWrapper::Exception::Params' );
Class::AlzaboWrapper::Exception::Params->Trace(1);

use Params::Validate qw( validate validate_with SCALAR UNDEF ARRAYREF HASHREF );
Params::Validate::validation_options
    ( on_fail =>
      sub { Class::AlzaboWrapper::Exception::Params->throw
                ( message => join '', @_ ) } );

my %TableToClass;
my %ClassAttributes;

BEGIN
{
    foreach my $sub ( qw( select update delete is_live ) )
    {
        no strict 'refs';
        *{ __PACKAGE__ ."::$sub" } = sub { shift->row_object->$sub(@_) };
    }
}

sub import
{
    my $class = shift;

    # called via 'use base'
    return unless @_;

    my %p =
        validate_with( params => \@_,
                       spec   =>
                       { caller => { type    => SCALAR,
                                     default => (caller(0))[0] },
                         base   => { type    => SCALAR,
                                     default => __PACKAGE__ },
                       },
                       allow_extra => 1,
                     );

    my $base = delete $p{base};

    $class->_make_methods(%p);

    eval "package $p{caller}; use base '$base'";
}

sub _make_methods
{
    my $class = shift;

    my %p = validate( @_,
                      { skip   => { type => ARRAYREF, default => [] },
                        table  => { isa => 'Alzabo::Table' },
                        caller => { type => SCALAR },
                      }
                    );

    my %skip = map { $_ => 1 } @{ $p{skip} };
    foreach my $name ( map { $_->name } $p{table}->columns )
    {
        next if $skip{$name};

        no strict 'refs';
        *{"$p{caller}\::$name"} = sub { shift->row_object->select($name) };

        $class->_record_attribute_creation( $p{caller} => $name );
    }

    {
        no strict 'refs';
        *{"$p{caller}\::table"} = sub { $p{table} };
    }

    $TableToClass{ $p{table}->name } = $p{caller};
}

sub _record_attribute_creation { push @{ $ClassAttributes{ $_[1] } }, $_[2] }

sub new
{
    my $class = shift;

    my @pk = $class->table->primary_key;

    my @pk_spec =
        map { $_->name => { type => SCALAR | UNDEF, optional => 1 } } @pk;

    my %p =
        validate_with( params => \@_,
                       spec =>
                       { object =>
                         { isa => 'Alzabo::Runtime::Row', optional => 1 },
                         @pk_spec,
                       },
                       allow_extra => 1,
                     );

    my %pk;
    foreach my $col (@pk)
    {
        if ( exists $p{ $col->name } )
        {
            $pk{ $col->name } = $p{ $col->name };
        }
    }

    my $row;
    if ( keys %pk == @pk )
    {
        $row = eval { $class->table->row_by_pk( pk => \%pk ) };
    }
    elsif ( exists $p{object} )
    {
        $row = $p{object};
    }
    else
    {
        $row = $class->_new_row(%p) if $class->can('_new_row');
    }

    return unless $row;

    my $self = bless { row => $row }, $class;

    $self->_init(%p) if $self->can('_init');

    return $self;
}

sub params_exception { shift; die @_ }

sub create
{
    my $class = shift;

    my $row =
        $class->table->insert
            ( values => { @_ } );

    return $class->new( object => $row );
}

sub potential
{
    my $self = shift;

    return
        $self->new( object => $self->table->potential_row( values => {@_} ) );
}

sub columns { shift->table->columns(@_) }
*column = \&columns;

sub cursor
{
    my $self = shift;

    return
        Class::AlzaboWrapper::Cursor->new
            ( cursor => shift );
}

sub row_object { $_[0]->{row} }

sub table_to_class { $TableToClass{ $_[1]->name } }

sub alzabo_attributes
{
    my $class = ref $_[0] || $_[0];

    @{ $ClassAttributes{$class} };
}


1;

__END__

=head1 NAME

Class::AlzaboWrapper - Higher level wrapper around Alzabo Row and Table objects

=head1 SYNOPSIS

  use Class::AlzaboWrapper ( table => $schema->table('User') );

=head1 DESCRIPTION

This module is intended for use as a base class when you are writing
a class that wraps Alzabo's table and row classes.

=head1 USAGE

Our usage examples will assume that there is database containing
tables named "User" and "UserComment", and that the subclass we are
creating is called C<WebTalk::User>.

=head2 Exceptions

This module throws exceptions when invalid parameters are given to
methods.  The exceptions it throws are objects which inherit from
C<Exception::Class::Base>, just as with Alzabo itself.

=head2 Import

When a subclass imports this module, it should pass a "table"
parameter to it, which should be an C<Alzabo::Runtime::Table> object.
This is considered the "main table" being wrapped by the given
subclass, though it can of course access other tables freely.

So for our hypothetical C<WebTalk::User> class, we would pass the
"User" table when importing C<Class::AlzaboWrapper>.

When importing the module, you can also pass a "skip" method, which
should be an array reference.  This reference contains the names of
columns for which methods should not be auto-generated.  See the
L<Generated methods section|/Generated methods> below for more details.

When you import the module, it will make sure that your class is
declared as a subclass of C<Class::AlzaboWrapper> automatically.

If invalid parameters are given when importing the module, it will
throw a C<Class::AlzaboWrapper::Exception::Params> exception.

=head2 Inherited methods

Subclasses inherit a number of method from C<Class::AlzaboWrapper>.

=head3 Class methods

=over 4

=item * new

The C<new()> method provided allows you to create new objects either
from an Alzabo row object, or from the main table's primary keys.

This method first looks to see if the parameters it was given match
the table's primary key.  If they do, it attempts to create an object
using those parameters.  If no primary key values are given, then it
looks for an parameter called "object", which should be an
C<Alzabo::Runtime::Row> object.

Finally, if your subclass defines a C<_new_row()> method, then this
will be called, with all the parameters provided to the C<new()>
method.  This allows you to create new objects based on other
parameters.

If your subclass defines an C<_init()> method, then this will be
called after the object is created, before it is returned from the
C<new()> method to the caller.

If invalid parameters are given then this method will throw a
C<Class::AlzaboWrapper::Exception::Params> exception.

=item * create

This method is used to create a new object and insert it into the
database.  It simply calls the C<insert()> method on the class's
associated table object.  Any parameters given to this method are
passed given to the C<insert()> method as its "values" parameter.

=item * potential

This creates a new object based on a potential row, as opposed to one
in the database.  Similar to the C<create()> method, any parameters
passed are given to the table's C<potential_row()> method as the
"values" parameter.

=item * columns

This is simply a shortcut to the associated table's C<columns> method.
This may also be called as an object method.

=item * column

This is simply a shortcut to the associated table's C<column> method.
This may also be called as an object method.

=item * table

This method returns the Alzabo table object associated with the
subclass.  This may also be called as an object method.

=item * alzabo_attributes

Returns a list of accessor methods that were created based on the
columns in the class's associated table.

=item * cursor ($cursor)

Given an C<Alzabo::Runtime::Cursor> object (either a row or join
cursor), this method returns a new C<Class::AlzaboWrapper::Cursor>
object.

=back

=head3 Object methods

=over 4

=item * row_object

This method returns the C<Alzabo::Runtime::Row> object associated with
the given subclass object.  So, for our hypothetical C<WebTalk::User>
class, this would return an object representing the underlying row
from the User table.

=item * select / update / delete / is_live

These methods are simply passthroughs to the underlying Alzabo row's
methods of the same names.  You may want to subclass some of these in
order to change their behavior.

=back

=head3 Generated methods

For each column in the associated table, their is a method created
that selects that column's value from the underlying row for an
object.  For example, if our User table contained "username" and
"email" columns, then our C<WebTalk::User> object would have
C<username()> and C<email()> methods generated.

As was mentioned before, if a column is listed in the "skip" parameter
when this module is imported, this method will not be made.

=head3 Class::AlzaboWrapper methods

The C<Class::AlzaboWrapper> module has a method it provides:

=over 4

=item * table_to_class ($table)

Given an Alzabo table object, this method returns its associated
subclass.

=back

=head3 Cursors

When using this module, you need to use the
C<Class::AlzaboWrapper::Cursor> module to wrap Alzabo's cursor
objects, so that objects the cursor returns are of the appropriate
subclass, not plain C<Alzabo::Runtime::Row> objects.

=head2 Subclassing

If you want to subclass this module, you may want to override the
C<import()> method in order to do something like create methods in the
calling class.  If you do this, you should call Class::AlzaboWrapper's
C<import()> method as well.  You'll need to override the "base" and
"caller" parameters when doing this.  Set "base" to your subclass and
"caller" to the class that called your import method.  Here is an
example:

  package My::AlzaboWrapper;

  use base 'Class::AlzaboWrapper';

  sub import
  {
      my $class = shift;

      # called via use base
      return unless @_;

      my %p = @_;

      my $caller = (caller(0))[0];

      $class->SUPER::import( %p,
                             base   => $class,
                             caller => $caller,
                           );

      $class->_make_more_methods(%p);
  }

=head3 Attributes created by subclasses

If you want to record the accessor methods your subclass makes so they
are available via C<alzabo_attributes()>, you can call the
C<_record_attribute_creation()> method, which expects two arguments.
The first argument is the class for which the method was created and
the second is the name of the method.

=head1 SUPPORT

The Alzabo docs are conveniently located online at
http://www.alzabo.org/docs/.

There is also a mailing list.  You can sign up at
http://lists.sourceforge.net/lists/listinfo/alzabo-general.

Please don't email me directly.  Use the list instead so others can
see your questions.

=head1 SEE ALSO

The Regional Vegetarian Guide at http://www.regveg.org/ is a site I
created which actually uses this code as part of the application.  Its
source is available from the web site.

=head1 COPYRIGHT

Copyright (c) 2002-2003 David Rolsky.  All rights reserved.  This
program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included
with this module.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
