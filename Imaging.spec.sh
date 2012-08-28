#!/bin/bash

#config
git_repo="git://github.com/LibreCat/Imaging.git";
git_basedir="Imaging";
rand=$RANDOM;
tempdir="/tmp";

#clone git repo and create source tar
workdir="$tempdir/$rand/$git_basedir"
temptar="$tempdir/$rand/$git_basedir.tar.gz"

mkdir -p "$tempdir/$rand" &&
trap "rm -rf $tempdir/$rand" SIGINT SIGTERM EXIT &&
echo "cloning to $workdir" &&
git clone $git_repo $workdir &&
tar czf $temptar --exclude=".git*" -C "$tempdir/$rand" $git_basedir &&
mv $temptar $HOME/rpmbuild/SOURCES/ &&

version=`cat version 2> /dev/null` &&
echo "version:$version" &&
number=`cat number 2> /dev/null` &&
number=$((number+1)) &&
echo "number:$number" &&
echo $number > number &&

#build
rpmbuild -ba --clean -vv /dev/stdin <<EOF
Name: $git_basedir
Summary: Dashboard application for scanning workflow at Ghent University Library
License: perl
Version: $version
Release: $version.$number
BuildArch: noarch
BuildRoot:  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires: perl >= 5.10,pcre,pcre-devel
Source: %{name}.tar.gz

%description

%prep
%setup -q -n %{name}
%filter_provides_in -P .
%filter_requires_in -P .
%filter_setup

%build
echo "nothing to build"

%install
%{__rm} -rf %{buildroot}

%{__mkdir} -p %{buildroot}/opt/%{name}
%{__mkdir} -p %{buildroot}/etc/init.d
%{__mkdir} -p %{buildroot}/var/log/%{name}
%{__mkdir} -p %{buildroot}/etc/cron.d

%{__cp} -r \$RPM_BUILD_DIR/%{name}/* %{buildroot}/opt/%{name}/
%{__cp} \$RPM_BUILD_DIR/%{name}/init.d/%{name}.init %{buildroot}/etc/init.d/%{name}
%{__cp} \$RPM_BUILD_DIR/%{name}/cron.d/* %{buildroot}/etc/cron.d

echo "Complete!"

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-,root,root,-)
/opt/%{name}/
/etc/init.d/%{name}
/etc/cron.d
%doc

%post
(
cd /opt/%name &&
perl Build.PL &&
yes | ./Build installdeps &&
%{__mkdir} -p /var/log/%{name}/ &&
test -d /var/log/%{name}/ &&
chmod +x /etc/init.d/%{name} &&
chmod 644 /etc/cron.d/imaging-* &&
chkconfig --add %{name} && chkconfig --level 345 %{name} on && service %{name} start &&
echo "service %{name} installed!" &&
./Build realclean
) || exit 1

%preun
service %{name} stop && chkconfig --del %{name}
echo "service %{name} removed"

%changelog
EOF
