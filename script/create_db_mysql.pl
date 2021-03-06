use strict;
use warnings;
use utf8;
use Data::Dumper;
use Encode;

use DBI qw(:utils);

use Zonemaster::WebBackend::Config;

die "The configuration file does not contain the MySQL backend" unless (lc(Zonemaster::WebBackend::Config->BackendDBType()) eq 'mysql');
my $db_user = Zonemaster::WebBackend::Config->DB_user();
my $db_password = Zonemaster::WebBackend::Config->DB_password();
my $db_name = Zonemaster::WebBackend::Config->DB_name();
my $connection_string = Zonemaster::WebBackend::Config->DB_connection_string();

my $dbh = DBI->connect( $connection_string, $db_user, $db_password, { RaiseError => 1, AutoCommit => 1 } );

sub create_db {

    ####################################################################
    # TEST RESULTS
    ####################################################################
    $dbh->do( 'DROP TABLE IF EXISTS test_specs CASCADE' );

    $dbh->do( 'DROP TABLE IF EXISTS test_results CASCADE' );

    $dbh->do(
        'CREATE TABLE test_results (
			id integer AUTO_INCREMENT PRIMARY KEY,
			hash_id VARCHAR(16) DEFAULT NULL,
			domain varchar(255) NOT NULL,
			batch_id integer NULL,
			creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
			test_start_time TIMESTAMP,
			test_end_time TIMESTAMP,
			priority integer DEFAULT 10,
			progress integer DEFAULT 0,
			params_deterministic_hash character varying(32),
			params blob NOT NULL,
			results blob DEFAULT NULL,
			undelegated boolean NOT NULL DEFAULT false
		) Engine=InnoDB
        '
    );
    
    $dbh->do(
		'CREATE TRIGGER before_insert_test_results
			BEFORE INSERT ON test_results
			FOR EACH ROW
			BEGIN
				IF new.hash_id IS NULL OR new.hash_id=\'\'
				THEN
					SET new.hash_id = SUBSTRING(MD5(CONCAT(RAND(), UUID())) from 1 for 16);
				END IF;
			END;
		'
    );

    $dbh->do(
		'CREATE INDEX test_results__hash_id ON test_results (hash_id)'
    );
    
    ####################################################################
    # BATCH JOBS
    ####################################################################
    $dbh->do( 'DROP TABLE IF EXISTS batch_jobs CASCADE' );

    $dbh->do(
        'CREATE TABLE batch_jobs (
			id integer AUTO_INCREMENT PRIMARY KEY,
			username character varying(50) NOT NULL,
			creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
		) Engine=InnoDB;
        '
    );

    ####################################################################
    # USERS
    ####################################################################
    $dbh->do( 'DROP TABLE IF EXISTS users CASCADE' );

    $dbh->do(
        'CREATE TABLE users (
			id integer AUTO_INCREMENT primary key,
			username varchar(128),
			api_key varchar(512),
			user_info blob DEFAULT NULL
		) Engine=InnoDB;
        '
    );
}

create_db();
