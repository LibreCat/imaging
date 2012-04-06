CREATE TABLE IF NOT EXISTS users (
	id int(11) NOT NULL AUTO_INCREMENT,
	name varchar(255) DEFAULT NULL,
	login varchar(255) NOT NULL,
	password mediumtext NOT NULL,
	roles mediumtext,
	directory_ready varchar(1024) not NULL,
	directory_reprocessing varchar(1024) not NULL,
	PRIMARY KEY (id),UNIQUE(name),UNIQUE(login)
) ENGINE=INNODB DEFAULT CHARSET=utf8;

create table profiles (
	id integer not NULL auto_increment,
	name varchar(1024) not NULL,
	PRIMARY KEY(id)
)engine=innodb DEFAULT CHARSET=utf8;

create table test_packages (
	id integer not NULL auto_increment,
	name varchar(1024) not NULL,
	PRIMARY KEY(id)
);

create table locations (
	id varchar(1024) not NULL,
	user_id integer not NULL references users(id)
	path varchar(1024) not NULL,
	type varchar(256) not NULL,
	status varchar(256) not NULL default "error",
	PRIMARY KEY(id)
)engine=innodb DEFAULT CHARSET=utf8;

create table files (
	id integer not NULL auto_increment,
	path varchar(2048) not NULL,
	location_id integer not NULL references locations(id),
	PRIMARY KEY(id),
	UNIQUE(id,location_id),
	UNIQUE(path)
)engine=innodb DEFAULT CHARSET=utf8;

create table log (
    id integer not NULL auto_increment,
    location_id integer not NULL references locations(id),
    PRIMARY KEY(id),
	data longblob not null,
    UNIQUE(id),
	UNIQUE(location_id),
)engine=innodb DEFAULT CHARSET=utf8;
