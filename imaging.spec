Name: imaging
Summary: Dashboard application for scanning workflow at Ghent University Library
License: perl
Version: 1.0
Release: 1
BuildArch: noarch
BuildRoot:  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
Requires: perl >= 5.10,pcre,pcre-devel,expat,expat-devel,libxml2-devel
Source: %{name}.tar.gz
 
%description
 
%prep
%setup -q -n %{name}
%filter_provides_in -P .
%filter_requires_in -P .
%filter_setup 
 
%build
echo "Nothing to build"
 
%install
%{__rm} -rf %{buildroot}
 
%{__mkdir} -p %{buildroot}/opt/%{name}
%{__mkdir} -p %{buildroot}/etc/init.d
%{__mkdir} -p %{buildroot}/var/log/%{name}
 
%{__cp} -r \$RPM_BUILD_DIR/%{name}/* %{buildroot}/opt/%{name}/
%{__cp} \$RPM_BUILD_DIR/%{name}/init.d/%{name}.init %{buildroot}/etc/init.d/%{name}
 
echo "Complete!"
 
%clean
%{__rm} -rf %{buildroot}
 
%files
%defattr(-,root,root,-)
/opt/%{name}/
/etc/init.d/%{name}
%doc
 
%post
(
cd /opt/%name &&
unlink %name &&
perl Build.PL &&
yes | ./Build installdeps &&
%{__mkdir} -p /var/log/%{name}/ &&
test -d /var/log/%{name}/ &&
chmod +x /etc/init.d/%{name} &&
chkconfig --add %{name} && chkconfig --level 345 %{name} on && service %{name} start &&
echo "service %{name} installed!" &&
./Build realclean
) || exit 1
 
%preun
service %{name} stop && chkconfig --del %{name}
echo "service %{name} removed"
 
%changelog
