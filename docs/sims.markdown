# Synopsis #

Generating useful test data for applications is hard. The standard practices all
suck. The DBIx::Class extension DBIx::Class::Sims (aka Sims) provides a much
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
DBIx::Class::Fixtures). When you run your tests, you would drop and recreate the
database, load the snapshot into the database, then run your test.

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

A. Take the 3 days to rework all the fixtures by hand?
A. Take the 3 days to build a tool to migrate all the fixtures?
   * Note this will require user input to pick the right value in some cases.
A. Consolidate the fixtures into 3 different scenarios?
A. Skip the tests?

Most teams end up choosing option D. If your team is really disciplined, you may
end up with options B or C. No-one does option A, even though that's what I keep
hearing whenever I bring up this problem.

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

If we use an ORM, such as DBIx::Class, we have already provided our application
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

## 

## Attributes ##

The other major part of the puzzle is what goes into the columns for the various
rows we're creating. When you use fixtures, the values are frozen in time. You
are using "John Smith" who purchased a "red ball" at "2012-05-03 10:44:33" every
single time.

This can be valuable - identical inputs should result in identical ouputs every
single time. (And, if that's your use-case, the Sims has you covered.) But, most
tests want to use a variety of inputs, across as wide variety of
"reasonable-looking" as possible. So, whatever tool we use should do just that.
(And, the Sims does. More on this later.)

## Time stops for no-one ##

In the previous section, the example was of "John Smith" buying a "red ball" at
a specfic time. When the test was written, it's like that the date was either
very close to the date the test was written or not too far into the future.
(When I do archaeological code surveys for clients, that's one of the markers I
look for.) But, our application takes specific actions if the purchase is dated
before or after today. Our tests need to exercise both paths, so we need to have
test cases that do just that.

The obvious way is to have the "before" test use "2000-01-01" and the "after"
test use "2100-01-01" (or somesuch). But, does that really exercise what you
want your application to be doing? How many times are you going to receive a
purchase that is over `2100-($curdate{years}+1)` years into the future. It's
much better to exercise your application with values much closer to today. But,
your fixtures are **frozen** in time. That's their claim to fame - you cannot up
and change them willy-nilly.

(And, yes, the Sims handles this case, too.)

# The Sims way #

You've already seen an example of how the Sims looks.
```perl
$schema->load_sims({
    Invoice => [
        {}, {}, {}, {}, {},
    ],
});
```

# Not everything is a test #

Every example so far has been in the context of a test. That is the major
use-case for something like the Sims. But, there are other places where it can
come in handy.

# Author #

Rob Kinyon <rob.kinyon@gmail.com> is a long-time developer and contributor to
both CPAN and DBIx::Class. He's written several articles on perl.com and can be
found at http://robonperl.blogspot.com/, @rkinyon on Twitter, and robkinyon on
IRC.
