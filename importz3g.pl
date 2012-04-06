#!/usr/bin/perl
use DBI;
# you also need DBD:SQLite;

print '<?xml version="1.0" encoding="UTF-8"?>'."\n";
print '<descriptions>'."\n";

my $dbh = DBI->connect("dbi:SQLite:development.sqlite3", "", "",
{RaiseError => 1, AutoCommit => 1});
my $sth = $dbh->prepare("select filename, name, description from broadcasts where filename is not null or filename <> ''");
$sth->execute();
while(my $result = $sth->fetchrow_hashref()) {
    print '<d filename="'.$result->{'filename'}.'">'."\n";
    print '<name>'.$result->{'name'}.'</name>'."\n";
    print '<txt>'.$result->{'description'}.'</txt>'."\n";
    print '</d>'."\n";
}

$sth->finish();
$dbh->disconnect;
print '</descriptions>'."\n";

