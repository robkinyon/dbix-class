# Synopsis #

Generating useful test data for applications is hard. The standard practices all
suck. The `DBIx::Class` extension `DBIx::Class::Sims` (aka Sims) provides a much
better solution.

# The Problem #

There are a few constants when developing applications that use databases
(whether for the web or not).

1. Your application's interactions with your database are complicated.
1. Your database schema is going to change. Often.
1. You, the developer, aren't going to be aware of much of the earlier points.

The quicker everything changes, the more you want tests. Lots and lots of tests.
But, of course, the quicker everything changes, the harder it becomes to write
tests against the database.

# Fixtures - the solution that hurts #

The obvious solution to solve this conundrum is something called *fixtures*. 
Fixtures are a snaphot in time of the data you intend to use. You build up the
data as you need and take a dump of it (using some tool such as to mydumper or
`DBIx::Class::Fixtures`). When you run your tests, you would drop and recreate
the database, load the snapshot into the database, then run your test.

At first, this works so well. You can even take the snapshot from production to
reproduce bugs reported by users and build your regression test suite.

## Where things go wrong ##

Fixtures address problem #1 ("Things are complicated") quite nicely. But, they
fail horribly when confronted with problem #2 ("Everything changes"). At first,
it's just one of the table your unit test is concerned with. A new column is
added that doesn't have a default value or an existing column changes type and
the old values no longer work. So, you shrug and modify the fixtures so that the
tests pass again.

Then, the first domino falls. You're working on a page in the admin section and
you add a required column to the users table. The admin section tests run clean,
so you submit your changeset for code review, it passes, and heads to Jenkins
for continuous integration. Proud of yourself, you head to lunch, only to return
to find 70% of tests are now failing. It turns out that the users table is a
parent for several of the key tables and now all the fixtures for all the tests
are broken.

Now, you're stuck with a "Problem"(tm). There are several dozen fixtures in use
across the 400+ tests in your test suite. Do you:

1. Take the 3 days to rework all the fixtures by hand?
1. Take the 3 days to build a tool to migrate all the fixtures?
   * Note this will require user input to pick the right value in some cases.
1. Consolidate the fixtures into 3 different scenarios?
1. Skip the tests?

Most teams end up choosing option 4. If your team is really disciplined, you may
end up with options 2 or 3. No-one does option 1, even though that's what I keep
hearing people swear they'll do whenever I bring up this problem.

And this is just adding a column in one table. What happens if the change is to
add a new table or to refactor a large chunk of tables?

## The root of the issue ##

The real problem with fixtures for tests is that it requires the test to know
about parts of the system that aren't under test. For example, if your test is
focused on the interaction of invoices and lineitems when doing returns, why
should adding a column to the users table affect this? If you're using fixtures,
it's because invoices has a FK to sales which has a FK (buyer\_id) to users.
Since those are non-NULL'able foreign keys, we have to have a value, *even
though that row makes no difference to the test*. (Yes, for some tests of the
return logic, it might matter, but not for *this* test.)

The ideal, from a test-writing perspective, is to say "I want these things" and
something, somewhere, figures out how to build them. And anything those things
need in order to exist. My test shouldn't know about those things.

More to the point, every test should be resilient to any changes outside the
specific areas the test is focused on. If I have a test that focuses on invoices
and lineitems, changes to the users table shouldn't affect it. And vice versa.

# Our dream tool #

If we use an ORM like `DBIx::Class`, we have already provided our application
with all the information it needs to create any necessary rows. The ORM already
knows what all the foreign keys are - we've told it through the belongs\_to and
has\_many relationships. So, now when we ask for "two invoices", a row in the
sales table and its corresponding seller in the users table can be created in
addition to the two rows in the invoices table.

Let's start to build up what our ideal tool would do by starting with our dream
invocation. So, maybe something like:
```perl
my @invoices = do_magic_thing({
    invoices => 2,
});
```
It's got "magic" in the name - a good start! `do_magic_thing()` would ideally do
this:

1. Drop and recreate the database.
1. Create everything our two invoice rows would need.
1. Create our two invoice rows, populating the columns with "reasonable-looking"
values.
1. Return back the row objects that it created so we can build on them in our
test.

## Attributes ##

The other major part of the puzzle is what goes into the columns for the various
rows we're creating. When you use fixtures, the values are frozen in time. You
are using "John Smith" who purchased a "red ball" at "2012-05-03 10:44:33" every
single time.

This can be valuable - identical inputs that result in identical ouputs every
single time are a good test. So, let's see if we can replicate that with our
dream invocation. We're going to have to change it to support setting attributes
on a per-row basis. Maybe, instead of a number of invoices to create, let's
pass an array of hashes. If a column is set in the hash, then that value is put
into the row.
```perl
my @invoices = do_magic_thing({
    invoices => [
        { date_purchased => '2012-05-03 10:44:33' },
        {},
    ],
});
```
We care about the first invoice's date_purchased, but not for the second
invoice. This takes care of one of the three values we want to keep fixed.

## Multiple tables ##

The other two values are on different tables. Let's try just adding those tables
into our magic invocation and see what it looks like:
```perl
my @invoices = do_magic_thing({
    invoices => [
        { date_purchased => '2012-05-03 10:44:33' },
        {},
    ],
    products => [
        { name => 'red ball' },
    ],
    users => [
        { name => 'John Smith' },
    ],
});
```
The first thing that pops out is the return value. It's not just invoices
anymore. It needs to be all the rows. But, figuring out which objects correspond
to which rows could get annoying. This function is *magic*, so it should do as
much of the figuring for us. Maybe, it could give us back a data structure that
is exactly like the one we give it, just with the hashrefs filled in. Instead of
`@invoices`, we would get back `$objects`, a hashref of arrays of objects that
could look like:
```perl
$objects = {
    invoices => [
        $row1_with_date_purchased_set,
        $row2_with_nothing_set,
    ],
    products => [
        $row1_with_red_ball,
    ],
    users => [
        $row1_with_john_smith,
    ],
};
```

## Connections ##

Now, we have rows in three tables - invoices, products, and users. But, these
rows don't exist in a void by themselves. There are connections and linkages so
that we get "John Smith" purchasing a "red ball" at "2012-05-03 10:44:33". It
would be great if, when a row is created and it needs a parent row in some other
table, it would use an existing row in that table if possible. This way, by
creating the rows in the products and users tables, the linkage rows in the
sales and lineitems tables would use those rows without us having to say so.
Since it makes our lives easier, let's assume that this happens.

To be formal, let's expand our specification to say that when a row in a table
is needed and nothing has been said about it, the following steps will take
place:

1. If no rows exist, a row will be created with default values
1. A random row from that table will be selected and used.

## Relationships ##

Our magic invocation is starting to take shape. Our test involving "John Smith"
buying a "red ball" at "2012-05-03 10:44:33" has been coded up and has worked
great, even when a new column was added to the lineitems table. Problem solved,
right? Not quite.

One of our users has just reported a bug where they bought two products in the
same sale, but each was on their own invoice. How will our magic invocation
handle this? Our first stab is just to add the second product - a "blue car" -
but that's not working right. Can you see the problem?
```perl
my $objects = do_magic_thing({
    invoices => [
        { date_purchased => '2012-05-03 10:44:33' },
        {},
    ],
    products => [
        { name => 'red ball' },
        { name => 'blue car' },
    ],
    users => [
        { name => 'John Smith' },
    ],
});
```
About half the time, our two invoices both have the same product. It's because
of our formal specification for connections. We need to explicitly link the
first invoice to the "red ball" and the second invoice to the "blue car". But,
there are no columns on the invoices table to do that - the foreign key back to
invoices is on the lineitems table. It would suck if we had to explicitly have a
lineitems entry. We don't care about the lineitems objects, so why would we have
talk about them?

What we really want is to be able to specify the *relationship* between the
invoices and products tables *through* the lineitems table. If we were using the
object graph of `DBIx::Class`, we could do something like
```perl
$invoice->add_lineitems([
    {
        # Other columns here ...
        product => $schema->resultset('Product')->search({
            name => 'red ball'
        }),
    },
]);
```
"Other columns here" sounds just like the hand-waving we've been doing with our
magic invocation. Maybe, our magic invocation needs to know about `DBIx::Class`
relationships *as well as* the table's columns. While we're at it, why are we
even thinking about tables. We don't care about the database tables so much as
we care about the `DBIx::Class` objects. So, let's stop using the table names
and start using the `DBIx::Class` source names. Once we do that, we can start
using the relationships we've already defined.
```perl
my $objects = do_magic_thing({
    Invoice => [
        {
            date_purchased => '2012-05-03 10:44:33',
            lineitems => [
                { product => { name => 'red ball' } },
            ],
        },
        {
            lineitems => [
                { product => { name => 'blue car' } },
            ],
        },
    ],
    User => [
        { name => 'John Smith' },
    ],
});
```
Hmmmm. We no longer get back the products in our `$objects`, but that's okay. We
didn't really care about them, anyways. We just wanted to make sure that the two
products were different. And, this is much more explicit about what we actually
do care about - the invoices.

## Column sim types ##

Now that we've removed the products from our top-level list of things we care
about, it would be awesome if we could remove the user from that list, too. But,
the user's name is a non-NULL value and there isn't a default value for it. The
actual value in the name doesn't really matter - "John Smith" was just the name
some developer picked who no longer works here. But, the name has to be
"reasonable-looking" - "AS#*1EQsdfa82..0 sx/?/" isn't a good test case. So, in
the spirit of magic invocations and leaning on the fact that we're now using our
`DBIx::Class` objects, let's say that we can add something to the user's name
column definition that says "When the Sims wants a value, create a random and
reasonable-looking name." Maybe, we can modify the `__PACKAGE__->add_columns()`
call to something like:
```perl
# In My/Schema/Result/User.pm
__PACKAGE__->add_columns(
    # some columns here ...
    name => {
        type => 'varchar',
        size => 100,
        nullable => 0,
        sim => {
            type => 'name',
        },
    },
    # other columns here ...
);
```
We've already seen how we end up needing to extend things. It's pretty easy to
see how we might want zipcodes, addresses, phone numbers, email addresses - all
kinds of things that could use a reasonable-looking value. So, let's make sure
we can easily handle those.

This type "name" should return back all sorts of possible names - everything
from "John Smith" to "Jane Doe" to "Dr. Orville G. Wilkerson III, Esq" to
"Mukabu". The goal is to have names that are "reasonable-looking", but will
challenge our code to do the right thing under a variety of circumstances.

We can formalize this, too - at least in a way. If a column contains values
that are regular in some fashion, we should be able to have some *generator*
that generates values according to some pattern or rule. We'll call these
generators *types* or "sim\_types".

Since the name is being set for us, we can remove the user from our magic
invocation. Now, it looks like:
```perl
my $objects = do_magic_thing({
    Invoice => [
        {
            date_purchased => '2012-05-03 10:44:33',
            lineitems => [
                { product => { name => 'red ball' } },
            ],
        },
        {
            lineitems => [
                { product => { name => 'blue car' } },
            ],
        },
    ],
});
```
This is better because we never cared about the user. So, the user's name column
could be refactored into a first_name and last_name or even removed to some
other table and our test doesn't break. We're down to exactly and only what we
care about in this test.

## Business-specific names ##

Well, not quite only what we care about. We're still specifying product names in
our magic invocation. Just like the user's name, we don't really care what these
products are called. We want to be protected against the same kind of changes to
the name column in the products table as in the users table. But, there isn't a
regular pattern for the generation of product names. It's unique to our business
what a product could be called. So, we need a way to generate values that are
specific to us. In the same way that we were able to specify a type, it would be
awesome if we could specify a function that runs whenever a value is needed for
that column and its return value would be the value used. So, let's say we have
something like:
```perl
# In My/Schema/Result/Product.pm
__PACKAGE__->add_columns(
    # some columns here ...
    name => {
        type => 'varchar',
        size => 100,
        nullable => 0,
        sim => {
            func => sub {
                my @colors = qw( red yellow pink green purple orange blue );
                my @toys = qw( ball fish bow tree panda cat car );
                return join( ' ',
                    $colors[rand @colors],
                    $toys[rand @toys],
                );
            },
        },
    },
    # other columns here ...
);
```
This is nice because it reuses the same sort of functionality that the "name"
type introduced, but instead of a "type", we have a "func" (short for function).
This will create product names like "red bow" or "pink tree" or even "blue car".
The names will be random, but "reasonable-looking". Hopefully, they will even
occassionally cause a test to fail, exposing subtle bugs in our application.

Now, our magic invocation would look like this:
```perl
my $objects = do_magic_thing({
    Invoice => [
        {
            date_purchased => '2012-05-03 10:44:33',
            lineitems => [
                { product => {} },
            ],
        },
        {
            lineitems => [
                { product => {} },
            ],
        },
    ],
});
```
We're specifying that we want to create a new product for each lineitem, but we
don't care what goes into that product, so long as it's different from the
previous one. This is exactly what the bug report described, but generalized out
instead of being specifically about red balls and blue cars. (Though, as we've
already seen, if the bug was about those specific products, we can still capture
that.)

## Time stops for no-one ##

Over the past few iterations, we've been stripping out one hard-coded aspect of
our test specification after another. Other than the relationships, we're down
to just one last thing - the date. When the test was written, the date was
either just before today or just after. (When I do archaeological code surveys
for clients, that's one of the markers I look for.) But, our application takes
specific actions if the purchase is dated before or after today. Our tests need
to exercise both paths, so we need to have test cases that do just that.

The obvious way is to have the "before" test use "2000-01-01" and the "after"
test use "2100-01-01" (or somesuch). But, does that really exercise what we want
our application to be doing? How many times are we going to receive a purchase
that is over `2100 - ($curdate{years} + 1)` years into the future. It's much
better to write our test with values much closer to today, whatever the today
the test is run on.

Back to our magic invocation, we'd love to be able to say "yesterday" or "today"
or some other date-time type magic. In fact, I think it would be great if we
could, at runtime, pass in the same sim information that we have been adding to
the column definitions.
```perl
my $objects = do_magic_thing({
    Invoice => [
        {
            date_purchased => magic_type( time => 'yesterday' ),
            lineitems => [
                { product => {} },
            ],
        },
        {
            lineitems => [
                { product => {} },
            ],
        },
    ],
});
```
Of course, we could do all the date arithmetic ourselves before the call to
`do_magic_thing()`, but why should we when we have a magic invocation that does
all that work for us?

# Making the magic real #

Our magic invocation `do_magic_thing()` is starting to look like a real function
we could write. It's become pretty obvious that the only object with information
about all the sources in our schema is, well, the `$schema` object. So,
`do_magic_thing()` is going to be a method on a `DBIx::Class::Schema` object.
Something like this would work:
```perl
my $objects = $schema->load_sims({
    Invoice => [
        {
            date_purchased => \{ type => time, value => 'yesterday' },
            lineitems => [
                { product => {} },
            ],
        },
        {
            lineitems => [
                { product => {} },
            ],
        },
    ],
});
```
The only other change is the use of the HASHREFREF instead of `magic_type()`.
Because `load_sims()` is a method on the `$schema` object, there's no way to
ensure that there will be a function imported into every possible namespace that
the `$schema` object could be passed to. We cannot pass in a hashref because
that's the interface for specifying the columns of a parent object. But, nothing
(currently) uses a HASHREFREF, or a reference to a hashref. So, we can
appropriate that for our purposes. (`DBIx::Class` uses REF and ARRAYREFREF for
various purposes, but not HASHREFREF.)

# Not everything is a test #

Our meander down the garden path has been about writing better, more resilient
tests that don't deal with things they don't care about. That is the major
use-case for something like the Sims. But, there are other places where it can
come in handy. For example, data for developers to work with.

## Developers and Their Data ##

At first, before the application goes live, the only data lives in a developer's
database. After go-live, the primary source of data ends up in production and a
process is usually set up to restore the nightly production backup to the QA and
developer databases. While this process is appealing because it both verifies
the production backup and provides seemingly useful data to developers, it has
several flaws to it.

The easiest flaw to fix is that customer data is visible to developers. Most
teams end up creating a fuzzing procedure as part of their restore process,
which generally takes care of it.

The second problem is the size of the data. After a few months, the database
quickly approaches several dozen gigabytes. If every developer has a copy of the
database, that rapidly becomes very unwieldy. Most teams end up trying to build
a way of stripping out most of the extraneous data, which never works. So, they
build a huge set of fixtures, and we all know how that works out.

The third problem is the composition of the data. You'd think that production
data has everything in it. Every scenario is represented somewhere and all a our
developer has to do is pick the right user or company or invoice and their work
will flow. Except, we know that's just not true. Every developer picks a couple
specific whatevers to develop against, not realizing they're missing this issue
or that problem.

## Demonstrations of good faith ##

Your salesfolk, at some point, are going to want to do a demonstration to some
prospective clients or to a trade show or in a presentation to a group. They
will have a dog and pony show they want to walk through - a narrative they want
the listeners to follow. They will create a set of users, companies, products,
and so forth that they want to have in the database.

How will that set be maintained? Will you create a set of fixtures for it? After
all of this, I would hope not.

# Closing #

In this brave new world of agile development, test data has to be more than an
afterthought. Generating good test data requires a lot of knowledge about how
the database is structured and how the pieces interrelate. That knowledge
changes rapidly over time as your application changes. This change is good, so
we have to embrace it. Luckily, `DBIx::Class` encapsulates the vast majority of
those changes, allowing you to think solely about the data you want to test and
leaving the rest of the complexities to the Sims.

# Author #

Rob Kinyon <rob.kinyon@gmail.com> is a long-time developer and contributor to
both CPAN and `DBIx::Class`. He's written several articles on perl.com and can
be found at http://robonperl.blogspot.com/, @rkinyon on Twitter, and robkinyon
on IRC.
