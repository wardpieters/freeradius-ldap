#!/bin/bash
LDAP_HOST="${LDAP_HOST:-ldap1.example.com ldap2.example.com}"
LDAP_PORT="${LDAP_PORT:-389}"
LDAP_USER="${LDAP_USER:-cn=admin,dc=example,dc=com}"
LDAP_PASS="${LDAP_PASS:-password}"
LDAP_BASEDN="${LDAP_BASEDN:-dc=example,dc=com}"
LDAP_USER_BASEDN="${LDAP_USER_BASEDN:-ou=Users,dc=example,dc=com}"
LDAP_GROUP_BASEDN="${LDAP_GROUP_BASEDN:-ou=Groups,dc=example,dc=com}"
LDAP_CLIENT_BASEDN="${LDAP_CLIENT_BASEDN:-ou=Clients,dc=example,dc=com}"

LDAP_RADIUS_ACCESS_GROUP="${LDAP_RADIUS_ACCESS_GROUP:-}"
RADIUS_CLIENT_CREDENTIALS="${RADIUS_CLIENT_CREDENTIALS:-}"

# to turn on debugging, use "-x -f -l stdout"
RADIUSD_ARGS="${RADIUSD_ARGS:--f -l stdout}"

ldap_subst() {
    sed -i -e "s/${1}/${2}/g" /etc/raddb/mods-available/ldap
}

# substitute variables into LDAP configuration file
ldap_subst "@LDAP_HOST@" "${LDAP_HOST}"
ldap_subst "@LDAP_PORT@" "${LDAP_PORT}"
ldap_subst "@LDAP_USER@" "${LDAP_USER}"
ldap_subst "@LDAP_PASS@" "${LDAP_PASS}"
ldap_subst "@LDAP_BASEDN@" "${LDAP_BASEDN}"
ldap_subst "@LDAP_USER_BASEDN@" "${LDAP_USER_BASEDN}"
ldap_subst "@LDAP_GROUP_BASEDN@" "${LDAP_GROUP_BASEDN}"
ldap_subst "@LDAP_CLIENT_BASEDN@" "${LDAP_CLIENT_BASEDN}"

# enable ldap
ln -s /etc/raddb/mods-available/ldap /etc/raddb/mods-enabled/ldap
ln -s /etc/raddb/mods-available/eap /etc/raddb/mods-enabled/eap

# configure the default site for ldap
sed -i -e 's/-ldap/ldap/g' /etc/raddb/sites-available/default
sed -i -e '/^#[[:space:]]*Auth-Type LDAP {$/{N;N;s/#[[:space:]]*Auth-Type LDAP {\n#[[:space:]]*ldap\n#[[:space:]]*}/        Auth-Type LDAP {\n                ldap\n        }/}' /etc/raddb/sites-available/default
sed -i -e 's/^#[[:space:]]*ldap/        ldap/g' /etc/raddb/sites-available/default

# configure the inner-tunnel site for ldap
sed -i -e 's/-ldap/ldap/g' /etc/raddb/sites-available/inner-tunnel
sed -i -e '/^#[[:space:]]*Auth-Type LDAP {$/{N;N;s/#[[:space:]]*Auth-Type LDAP {\n#[[:space:]]*ldap\n#[[:space:]]*}/        Auth-Type LDAP {\n                ldap\n        }/}' /etc/raddb/sites-available/inner-tunnel
sed -i -e 's/^#[[:space:]]*ldap/        ldap/g' /etc/raddb/sites-available/inner-tunnel

use_distro_provided_file() {
    # copy the distro-provided file to a new location if it
    # does not already exist
    [[ -f "${1}.dist" ]] || mv -f "${1}" "${1}.dist"
    # copy the distro-provided file to the original location
    cp -a "${1}.dist" "${1}"
}

# Make sure we always start with the original distro-provided copies of
# these files. On container restart, we will always repeat the same actions
# on unmodified copies, allowing the process to be idempotent.
use_distro_provided_file /etc/raddb/sites-available/default
use_distro_provided_file /etc/raddb/clients.conf

# configure the LDAP group for access
if [[ -n "$LDAP_RADIUS_ACCESS_GROUP" ]]; then
    # create a temporary file with the access rules so that sed can read
    # it into the correct place in the /etc/raddb/sites-available/default file
    # WARNING: radiusd is INCREDIBLY picky about the format
    cat > /root/ldap-radius-access-group << EOF
        # only allow access to a specific LDAP group
        if (Ldap-Group == "${LDAP_RADIUS_ACCESS_GROUP}") {
            noop
        }
        else {
            reject
        }

EOF

    sed -i -e '/^post-auth {$/r /root/ldap-radius-access-group' /etc/raddb/sites-available/default
fi

# setup clients
IFS=$',' read -ra RADIUS_CLIENT_CREDENTIALS_ARRAY <<< "$RADIUS_CLIENT_CREDENTIALS"
for i in "${RADIUS_CLIENT_CREDENTIALS_ARRAY[@]}"; do
    CLIENT="${i%%:*}"
    SECRET="${i#*:}"
    cat >> /etc/raddb/clients.conf << EOF
client $CLIENT {
    secret = $SECRET
    shortname = $CLIENT
    ipaddr = $CLIENT
    nas_type = other
}
EOF
done

# run radiusd
exec /usr/bin/tini -- /usr/sbin/radiusd $RADIUSD_ARGS
