# Synopsis #

The resultset is the most important concept in DBIx::Class. In many ways, it is
the foundational breakthrough behind the power of DBIx::Class. It is unique to
DBIC, but is frequently misunderstood.

This document explains what a resultset is, why you should care, and how you can
(ab)use resultsets for fun and profit.

# Notation #

Throughout this document, the following notations will be used:

* `$schema` is a DBIx::Class::Schema (or schema) object.
* `$source` is a DBIx::Class::ResultSource (or source) object.
* `$rs` is a DBIx::Class::ResultSet (or resultset) object. 
* `$row` is a DBIx::Class::Row (or row) object. 
* `My::Schema` is a generic schema class. It may have any classes necessary for
the examples.
* Artist and Album are the standard demo tables for DBIx::Class. These may have
any columns necessary for the examples.
* 'col1' and 'col2' are generic column names on any table. These may have any
type necessary for the examples.

# What is a resultset? #

First, what it is not. Unlike in most other ORMs, a resultset is **not** a
collection of rows that have been retrieved from the database. It is also not
the representation of a table in a database or a set of rows in a database.

A resultset, at its heart, is a (mostly) immutable object that knows how to
generate SQL queries. When you instantiate a resultset using
`$schema->resultset('Artist')`, you have an object that can generate the SQL.
```sql
SELECT me.col1, me.col2, ... FROM artists AS me
```

**Note**: The resultset isn't the SQL query - it's a query generator. This is
how new resultsets can be made from old ones.

# The search() method #

This is how the documentation normally describes the use of resultsets.
Normally, you see something like:
```perl
my $rs = $schema->resultset('Artist')->search({
    col1 => 'A',
    col2 => 'B',
});
```

The implication is the `$rs->search()` method is what instantiates a resultset.
This is only half true. The full truth is that both the `$schema->resultset()`
method is what initially *instantiates* a resultset. Its resultset is a "full"
resultset - if `$rs->all()` is called, it will return every row from the table.

The `$rs->search()` method, on the other hand, returns another resultset object
with the additional search criteria applied. This does not affect the original
`$rs`. (In fact, none of the ResultSet instance methods affect the invocant.) It
also does not communicate with the database.

Both of these methods just create new objects. You can call these methods as
many times as you want with no performance penalty. It is often a good way to
organize your program by iteratively building up resultsets. We'll see some
examples of this later.

# Relationships and JOINs #

Tables (and other sources of data) are represented in DBIx::Class by
ResultSource objects. This resultsource is what you are definining when you call
the methods on `__PACKAGE__` in your Row class. Sources have relationships to
each other. The most common relationship is represented in the database by a
foreign key (FK) and is considered a parent-child relationship. The row in the
child table *belongs\_to* a row in the parent table and the row in the parent
table row *has\_many* rows in the child table.

For the rest of this section, let's assume Artist is a parent table for Album.
The most common relationship definitions would look something like:
```perl
# In Result/Artist.pm
__PACKAGE__->has_many( albums => 'My::Schema::Result::Album' => 'artist_id' );

# In Result/Album.pm
__PACKAGE__->belongs_to( artist => 'My::Schema::Result::Artist' => 'artist_id' );
```

## Walking the object graph ##

The most common use of relationships is to walk the object graph. Once you have
a row in the parent `$artist`, you can say
```perl
my @albums = $artist->albums;
```

And, equivalently, when you have a row in the child `$album`, you can say
```perl
my $artist = $album->artist;
```

Both of those will do a query against the database when you invoke the methods.
(For how to avoid this additional query, see the Prefetching section below.)

## Walking JOINs ##

The relationship definitions also allow DBIx::Class to generate SQL queries that
have joins in them. For example, we may want to get all albums created by a
specific artist. We could do this:
```perl
my $artist = $schema->resultset('Artist')->search({
    name => 'Beethoven',
})->first;

my @albums= $artist->albums;
```
And that would work just fine. But, it's cumbersome and doesn't really describe
exactly what we're trying to accomplish.

Or, we could do this:
```perl
my @ablums = $schema->resultset('Album')->search({
    'artist.name' => 'Beethoven',
}, {
    join => 'artist',
})->all;
```

In this example, the difference isn't very large. But, imagine wanting to get a
list of all the albums from all artists whose hometown is in Austria and where
the name of the album's producer is 'Maury'. The query would look best like this
(assume the additional tables and relationships):
```perl
my @albums = $schema->resultset('Album')->search({
    'country.name' => 'Austria',
    'producer.name' => 'Maury',
}, {
    join => [
        artist => {
            hometown => country,
        },
        'producer',
    ],
})->all;
```

Reproducing that query by traversing the object graph would be very difficult to
write, impossible to maintain, and likely very very slow.

More on relationships and joins later.

# Searching #

In the documentation for `$rs->search()`, there are two parameters. The first
parameter corresponds to the WHERE clause. It is a data structure which is
handed off to SQL::Abstract for processing. In most cases, that's all you're
ever going to need. And, for the most part, that's what most ORMs will provide
for you. Well over 70% of the queries I've ever written with DBIx::Class only
use the first parameter.

## The WHERE clause ##

SQL::Abstract is a very powerful tool to build maintainable complex WHERE
clauses. A full discussion of its power is beyond this article, but here is an
example that could give you some ideas.
```perl
$artist_rs->search([
    name => [ 'Joe', 'Tim' ],
    {
        'producer.name' => { '!=' => 'Maury' },
        'producer.salary' => { '>=' => 100_000 },
        -and => [
            'first_album' => '2000',
            'last_album' => '2005',
        ],
    },
], {
    join => 'producer',
});
```
This translates to:
```sql
SELECT <columns>
FROM artist AS me
JOIN producer AS producer ON (artist.producer_id = producer.id)
WHERE me.name IN ( ?, ? )
OR (
    ( producer.name != ? AND producer.salary >= ? )
    AND
    ( first_album = ? OR last_album = ? )
)
```
With bind parameters of `'Joe', 'Tim', 'Maury', 100000, 2000, 2005`

A few things to note:
* The first parameter doesn't have to be a hashref. It can be an arrayref if
you want to OR clauses together.
* You can nest and chain AND and OR clauses together very easily.
* Operators can be specified, as can IN clauses.
* DBIx::Class passes all your values as bind parameters.
   * Where possible, it passes them in as the proper type, not just strings.

### The trapdoor ###

Sometimes, the SQL you want to use is either not supported by SQL::Abstract or
would be too cumbersome to specify that way. In that case, you can pass a string
reference at any point and the contents of that string will be put in verbatim
at that point. For example,
```perl
my $rs = $schema->resultset('Artist')->search(
    \"LEN(name) < LEN(producer.birthplace)",
    { join => 'producer' },
);
```
Note that I have passed in a string reference as the first parameter. This is
perfectly legal and the second parameter is still a hashref of options.

If you want to pass in bind parameters, you can use the ARRAYREFREF form.
```perl
my $input = $cgi->param('input1');
my $rs = $schema->resultset('Artist')->search(
    \[ "LEN(name) < LEN(producer.birthplace) OR LEN(?) > 5", $input ],
    { join => 'producer' },
);
```
While both of those queries are expressible in SQL::Abstract, it would be much
longer than one line.

**NOTE**: You are responsible for all quoting you may have to do. Normally,
DBIx::Class attempts to quote everything for you, but you are bypassing all the
protections DBIx::Class puts into place. Use this feature as sparingly as
possible.

**NOTE**: By doing this, you are injecting raw SQL into your DBIx::Class
queries. This means you lose all of the database independence you can have when
using DBIx::Class. For example, a common development pattern is to write tests
that use an in-memory SQLite database for speed and ease of maintenance, but
deploy on a database (such Postgres or Oracle). This becomes much harder if you
have raw SQL in your queries.

## The rest ##

The second parameter is where a lot of the magic happens. We've already seen it
in action to specify joins through relationships. You can also use it to
specify (among other things):

1. Limits and offsets
1. Which columns to retrieve.
   * Only retrieve the columns you need.
   * Retrieve a few columns from several other tables as well.
1. Ordering and grouping
1. Having clauses
1. Prefetching related rows. (More in the Prefetching section below)
1. Caching
   * This is useful only if you reuse a specific `$rs` object. It does **NOT**
   provide process-wide caching.

Some of these options have database-specific actions. For example, there is no
standard SQL extension for limits and offsets, so every database vendor has
developed there own. DBIx::Class works very hard to make sure the right flavor
of SQL is used for the database you've connected to.

Read through the documentation for DBIx::Class::ResultSet in the ATTRIBUTES for
more information on each one of these options (and more).

# Retrieving your rows #

So far, we've talked about how to create the perfect SQL query. We need to get
the data out of the database, at some point. DBIx::Class provides several ways
of retrieving your data.

## Get ALL the things! ##

`my @rows = $rs->all();` is the simplest way to retrieve data. Assuming you've
set up your `$rs` with the right search parameters, `@rows` will contain an
object of the right Row class for that data source. You most often see this
in for-loops or when passing the results of a query to a non-DBIx::Class-aware
function.

## Implicit Cursor ##

Another way of accessing your data is to use a cursor and a while loop.
ResultSets have a built-in implicit cursor, used as so:
```perl
my $rs = $schema->resultset('Artist')->search(...);
while ( my $row = $rs->next ) {
    # Do something useful with $row
}
```
And this behaves exactly as you'd expect.

### cached => 1 ###

Once the cursor is drained, the `$rs` will re-query the database if you ask it
for rows again. So, if you anticipate wanting to loop over the rows of a
resultset multiple times, you will want to use the "cache" option.
```perl
my $rs = $schema->resultset('Artist')->search(... , { cache => 1 });
while ( my $row = $rs->next ) {
    # Do something useful with $row
}

while ( my $row = $rs->next ) {
    # Do something else useful with $row
}
```

**NOTE**: This is a performance optimization and should be used sparingly, if at
all. Sprinkling this all over your codebase may cause other developers (such as
you 6 months from now) to be very confused.

## Other methods ##

There are several other methods that will return rows. Please read the
documentation for more inforamtion.

## When does the query actually happen? ##

DBIx::Class is lazy - it will only query the database when it absolutely has to.
Creating resultset objects doesn't communicate with the database. It is only
when you ask a resultset for a row object that it goes to the database.

When it does go to the database, it will get as much data as it knows it can get
in one call. So, it will retrieve all the columns in all the rows that match the
search criteria in the resultset.

This combination of lazy-where-possible and eager-when-required is a key design
driver for all of DBIx::Class. The `$schema` object won't even connect to the
database until it has to. But, once it has, it will ensure that it always has a
connection until told otherwise.

Like everything else in DBIx::Class, you're able to modify this behavior. For
example, you can choose to specify which columns you want to retrieve in the
second parameter to `$rs->search()`.

## Prefetching ##

A very common use case is to retrieve a set of rows, then iterate over them and
all of the rows of some has\_many relationship. Something like:
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
});

foreach my $artist ( $artists_rs->all ) {
    print "Artist: " . $artist->name . "\n";
    foreach my $album ( $artist->albums ) {
        print "    Album: " . $album->name . "\n";
    }
}
```

In the normal case (and what most other ORMs do), this would require 1+N SQL
queries. 1 for the query of the `artists` table and N for the N queries of the
`albums` table (where N i the number of artists).

DBIx::Class, of course, has a better solution. If we modify the query to be:
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
}, {
    prefetch => 'albums',
});
```
Then, all the albums will be fetched as part of the first query. This collapses
our 1+N queries into a single (very large) query. This first query will take a
little more time and uses up extra memory, but the overall runtime is reduced
quite significantly.

**NOTE**: prefetch should be treated as an *optimization* to be used only when
absolutely necessary. It should not be treated as a synonym for "join", even
though it currently behaves as one with respect to connecting tables. Remember -
this returns all the connecting rows. So, use it sparingly.

## HashRefInflator (HRI) ##

A common use for pulling data out of a database is to display it in a page of
some kind, usually by using a template to put things together. If we take our
prefetch example above, we might have the following Template Toolkit template:
```
[% FOR artist IN artists -%]
Name: [% artist.name %]
    [% FOR album IN artist.albums -%]
    Album: [% album.name %]
    [%- END %]
[%- END %]
```
and we could call it as so:
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
}, {
    prefetch => 'albums',
});

my $vars = {
    artists => [ $artist_rs->all ],
};
$tt->process( $template_name, $vars );
```

The problem here is that the template code can now modify our database. So, if
our template looked like:
```
[% FOR artist IN artists -%]
    [% artist.delete %]
[%- END %]
```
Instead of displaying useful things, that would delete every row from the
database that we passed into the template. One query at a time. From our
template. That would be a "Problem"(tm). 

DBIx::Class, again, has a solution.
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
}, {
    prefetch => 'albums',
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
});

# The rest same as before
```
Now, instead of being provided an array of My::Schema::Result::Artist objects,
the template receives an array of hashrefs containing the data of each artist.
The template can no longer interact with the database, even by mistake.

**NOTE**: This is also a performance boost. It's usually 1-2%, but sometimes
significantly higher. So, you should not sprinkle HRI all over your codebase
willy-nilly.

# Going beyond the search #

At the beginning, we discussed how the resultset is a query generator. This is
most evident in how you update or delete rows through DBIx::Class. You can call
update or delete on the Row objects, if that's appropriate. But, if you need
to update or delete multiple rows at once, then a resultset is more appropriate.
Given the following resultset:
```perl
my $rs = $schema->resultset('Artist')->search({
    'producer.name' => 'John',
}, {
    join => 'producer',
});

# Doing an update, issuing only one query
$rs->update({
    name => "One of John's artists",
});

# Doing a delete, issuing only one query
$rs->delete();
```

In short, `$rs->search` sets the WHERE clause that can then be used by SELECT,
UPDATE, or DELETE as needed.

# Extending the ResultSet #

Each Row class has a corresponding ResultSet class. You are encouraged to add
methods to this class to make your life easier. For example, you might have a
search you often apply to resultsets in a specific part of your application.
This search could be quite complex, spanning several lines. Instead of peppering
it all over the place, it's much better to put it in one place. Then, you can
apply that search to a given resultset very simply.
```perl
# In My::Schema::ResultSet::Artist
sub apply_studioA_restrictions {
    my $self = shift;

    return $self->search(
        # Crazy thing here
    );
}

# In your application code
$rs = $rs->apply_studioA_restrictions();
```

Note that we have to assign the return value back to the invocant. ResultSets
are (mostly) immutable objects.

# Relationships Redux #

## Relationships as ResultSets ##

When DBIx::Class traverses a relationship, it performs a search. All searches in
DBIx::Class are done with resultsets, so relationships are implemented under the
hood as resultsets. You can get access to the resultset underpinning a
relationship by calling the `X_rs` method. For example,
```perl
# Following a has_many relationship
my $album_rs = $artist->albums_rs;

# Following a belongs_to relationship
my $artist_rs = $album->artist_rs;
```

You can also specify search criteria in the relationship traversal.
```perl
my @albums = $artist->albums({ release_year => { '>' => 2000 } });

# Equivalent to
my @albums = $artist->albums_rs->search({
    release_year => { '>' => 2000 },
})->all;
```

## Multiple Relationships between Sources ##

There is no restriction on the number of relationships you can define between
two tables. For example, we might have albums table that tracks if an album has
been released yet. In most of our application's use-cases, we may only want to
deal with released albums. So, the standard `albums` relationship should be
restricted to albums where `released = 1`. But, we want to be able to access the
unreleased albums, if only in the one section of our application where we mark
them as released!
```perl
# In Artist.pm

# Get only released albums - this is the standard relationship usage.
__PACKAGE__->has_many(
    albums => 'My::Schema::Result::Album' => {
        'foreign.artist_id' => 'self.id',
        'foreign.released'  => 1,
    },
);

# Get all albums, released or not.
__PACKAGE__->has_many(
    all_albums => 'My::Schema::Result::Album' => 'artist_id',
);

# Get only unreleased albums
__PACKAGE__->has_many(
    unreleased_albums => 'My::Schema::Result::Album' => {
        'foreign.artist_id' => 'self.id',
        'foreign.released'  => 0,
    },
);
```

Like all relationships, each of these can be used when walking the object graph
**AND** in searches. In fact, you can use several of these *in the same search*.
For example, we want to find artists with a released album starting with 'A' or
an unreleased album set to release in 2020. (We have a far-thinking studio.)
```perl
my @artists = $schema->resultset('Artist')->search([
    'albums.name' => { -like => 'A%' },
    'unreleased_albums.release_year' => 2020,
], {
    join => [
        'albums', 'unreleased_albums',
    ],
});
```

# Useful extensions #

As you can imagine, there are dozens of modules on CPAN that extend the power of
DBIx::Class in various ways. Here is a short-list of useful ways to extend
resultsets.

## Applying these across your schema ##

frew, a prolific contributor to DBIx::Class, has already described how best to
apply multiple helpers and base classes across your entire schema. Please read
how to do it at http://search.cpan.org/~frew/DBIx-Class-Helpers-2.018004/lib/DBIx/Class/Helper/ResultSet.pm#NOTE

## DBIx::Class::Helper::ResultSet::AutoRemoveColumns ##

This will prevent large columns (TEXT, BLOB, etc) from being retrieved by
default. You can add them into a specific search with `+columns`, if you need to
retrieve them.

**Note**: If you don't specify `+columns`, you will be unable to retrieve the
large columns later.

If you want an easy to way to remove specific columns from a given search, look
at DBIx::Class::Helper::ResultSet::RemoveColumns instead.

## DBIx::Class::ResultSet::CorrelateRelationship ##

The synopsis says it all.

## DBIx::Class::ResultSet::Excel ##

This adds a method `export\_excel` that will take the current resultset's rows
and create an Excel file with the data.

## DBIx::Class::Helper::ResultSet::Shortcut ##

This helper really showcases the power of chaining resultsets. Normally, if you
want to modify a resultset (say, to order it), you have to execute a search with
an empty first parameter. Something like:
```perl
my $ordered_rs = $rs->search( undef, { order_by => [ 'col1', 'col2' ] } );
```
While that works, it's not as easy to read as
```perl
my $ordered_rs = $rs->order_by('col1,col2');
```

The helper adds a number of very useful shortcuts for manipulating resultsets in
various ways.

## DBIx::Class::Schema::ResultSetAccessors ##

This one is slightly different. It doesn't augment your resultsets, but augments
your schema. In the spirit of making things simple, this converts the following
code:
```perl
my $all_artists_rs = $schema->resultset('Artist');

# to

my $all_artists_rs = $schema->artists;
```
Some people may find the first form easier to work with, preferring the call to
`resultset()` important as a self-documenting marker. Others may find the second
form easier, preferring the more literate programming style. It's completely up
to you and your team.

# Closing #

You can use DBIx::Class as a Perl clone of other ORMs, treating your database as
an expensive key-value store of object graphs. And, you'll be just as successful
as if you'd written your application using one of those other ORMs. The concept
and implementation of the resultset, however, sets DBIx::Class far above the
rest in terms of the power, flexibily, and ease of use you gain. I hope I've
given you a good sense of how resultsets can make your code simpler, easier to
maintain, and faster.

# Author #

Rob Kinyon <rob.kinyon@gmail.com> is a long-time developer and contributor to
both CPAN and DBIx::Class. He's written several articles on perl.com and can be
found at http://robonperl.blogspot.com/, @rkinyon on Twitter, and robkinyon on
IRC.
