FROM centos:7
LABEL maintainer="Ward Pieters <docker@ward.nl>"

ENTRYPOINT [ "/init.sh" ]

# RADIUS Authentication Messages
EXPOSE 1812/udp

# RADIUS Accounting Messages
EXPOSE 1813/udp

# Install freeradius with ldap support
RUN yum -y install freeradius-ldap \
    && yum -y update \
    && yum -y clean all

# Install tini init
RUN curl -L https://github.com/krallin/tini/releases/latest/download/tini > /usr/bin/tini && chmod +x /usr/bin/tini

# Copy our configuration
COPY ldap /etc/raddb/mods-available/
COPY eap /etc/raddb/mods-available/
COPY init.sh /
