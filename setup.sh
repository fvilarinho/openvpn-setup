#!/bin/bash
# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Amazon Linux 2, Fedora, Oracle Linux 8, Arch Linux, Rocky Linux and AlmaLinux.
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function tunAvailable() {
	if [ ! -e /dev/net/tun ]; then
		return 1
	fi
}

function cidrToNetmask {
    local i
    local mask=""
    local full_octets=$(($1/8))
    local partial_octet=$(($1%8))

    for ((i=0; i<4; i+=1)); do
        if [ $i -lt $full_octets ]; then
            mask+=255
        elif [ $i -eq $full_octets ]; then
            mask+=$((256 - 2**(8-$partial_octet)))
        else
            mask+=0
        fi
        test $i -lt 3 && mask+=.
    done

    echo $mask
}

function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"

		source /etc/os-release

		if [[ $ID == "debian" || $ID == "raspbian" ]]; then
			if [[ $VERSION_ID -lt 9 ]]; then
				echo "⚠️ Your version of Debian is not supported."
				echo
				echo "However, if you're using Debian >= 9 or unstable/testing then you can continue, at your own risk."
				echo

				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done

				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		elif [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)

			if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
				echo "⚠️ Your version of Ubuntu is not supported."
				echo
				echo "However, if you're using Ubuntu >= 16.04 or beta, then you can continue, at your own risk."
				echo

				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done

				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		fi
	elif [[ -e /etc/system-release ]]; then
		source /etc/os-release

		if [[ $ID == "fedora" || $ID_LIKE == "fedora" ]]; then
			OS="fedora"
		fi

		if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
			OS="centos"

			if [[ $VERSION_ID -lt 7 ]]; then
				echo "⚠️ Your version of CentOS is not supported."
				echo
				echo "The script only support CentOS 7 and CentOS 8."
				echo

				exit 1
			fi
		fi

		if [[ $ID == "ol" ]]; then
			OS="oracle"

			if [[ ! $VERSION_ID =~ (8) ]]; then
				echo "Your version of Oracle Linux is not supported."
				echo
				echo "The script only support Oracle Linux 8."

				exit 1
			fi
		fi

		if [[ $ID == "amzn" ]]; then
			OS="amzn"

			if [[ $VERSION_ID != "2" ]]; then
				echo "⚠️ Your version of Amazon Linux is not supported."
				echo
				echo "The script only support Amazon Linux 2."
				echo

				exit 1
			fi
		fi
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2, Oracle Linux 8 or Arch Linux system"

		exit 1
	fi
}

function initialCheck() {
	if ! isRoot; then
		echo "Sorry, you need to run this as root"
		exit 1
	fi

	if ! tunAvailable; then
		echo "TUN is not available"
		exit 1
	fi

	checkOS
}

function installQuestions() {
	echo "Welcome to the OpenVPN installer!"
	echo "I need to ask you a few questions before starting the setup."
	echo "You can leave the default options and just press enter if you are ok with them."
	echo
	echo "I need to know the IPv4 address of the network interface you want OpenVPN listening to."
	echo "Unless your server is behind NAT, it should be your public IPv4 address."

	# Detect public IPv4 address and pre-fill for the user
	IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

	if [[ -z $IP ]]; then
		# Detect public IPv6 address
		IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	fi

	APPROVE_IP=${APPROVE_IP:-n}

	if [[ $APPROVE_IP =~ n ]]; then
		read -rp "IP address: " -e -i "$IP" IP
	fi

	#If $IP is a private IP address, the server must be behind NAT
	if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
		echo
		echo "It seems this server is behind NAT. What is its public IPv4 address or hostname?"
		echo "We need it for the clients to connect to the server."

		PUBLICIP=$(curl -s https://api.ipify.org)

		until [[ $ENDPOINT != "" ]]; do
			read -rp "Public IPv4 address or hostname: " -e -i "$PUBLICIP" ENDPOINT
		done
	fi

	if [[ -z $SERVER_NETWORK_PREFIX ]]; then
		echo

		until [[ $SERVER_NETWORK_PREFIX != "" ]]; do
			read -rp "Please enter the server network prefix, used for IP assignment to clients: " -e -i "10.8.0.0" SERVER_NETWORK_PREFIX
		done
  fi

	if [[ -z $SERVER_NETWORK_MASK ]]; then
		echo

		until [[ $SERVER_NETWORK_MASK != "" ]]; do
			read -rp "Please enter the server network mask, used for IP assignment to clients: " -e -i "24" SERVER_NETWORK_MASK
		done
  fi

	echo
	echo "What port do you want OpenVPN to listen to?"
	echo "   1) Default: 1194"
	echo "   2) Custom"
	echo "   3) Random [49152-65535]"

	until [[ $PORT_CHOICE =~ ^[1-3]$ ]]; do
		read -rp "Port choice [1-3]: " -e -i 1 PORT_CHOICE
	done

	case $PORT_CHOICE in
	  1)
		  PORT="1194"
		  ;;
	  2)
		  until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
			  read -rp "Custom port [1-65535]: " -e -i 1194 PORT
		  done
		  ;;
	  3)
		  # Generate random number within private ports range
		  PORT=$(shuf -i49152-65535 -n1)
		  echo "Random Port: $PORT"
		  ;;
	esac

	echo
	echo "What protocol do you want OpenVPN to use?"
	echo "UDP is faster. Unless it is not available, you shouldn't use TCP."
	echo "   1) UDP"
	echo "   2) TCP"

	until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
		read -rp "Protocol [1-2]: " -e -i 1 PROTOCOL_CHOICE
	done

	case $PROTOCOL_CHOICE in
	  1)
		  PROTOCOL="udp"
		  ;;
	  2)
		  PROTOCOL="tcp"
		  ;;
	esac

	echo
	echo "What DNS resolvers do you want to use with the VPN?"
	echo "   1) Current system resolvers (from /etc/resolv.conf)"
	echo "   2) Cloudflare (Anycast: worldwide)"
	echo "   3) Quad9 (Anycast: worldwide)"
	echo "   4) Quad9 uncensored (Anycast: worldwide)"
	echo "   5) FDN (France)"
	echo "   6) DNS.WATCH (Germany)"
	echo "   7) OpenDNS (Anycast: worldwide)"
	echo "   8) Google (Anycast: worldwide)"
	echo "   9) Yandex Basic (Russia)"
	echo "   10) AdGuard DNS (Anycast: worldwide)"
	echo "   11) NextDNS (Anycast: worldwide)"
	echo "   12) Custom"

	until [[ $DNS =~ ^[0-9]+$ ]] && [ "$DNS" -ge 1 ] && [ "$DNS" -le 13 ]; do
		read -rp "DNS [1-12]: " -e -i 1 DNS

		if [[ $DNS == "13" ]]; then
			until [[ $DNS1 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
				read -rp "Primary DNS: " -e DNS1
			done

			until [[ $DNS2 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
				read -rp "Secondary DNS (optional): " -e DNS2

				if [[ $DNS2 == "" ]]; then
					break
				fi
			done
		fi
	done

	echo
	echo "Do you want to use compression? It is not recommended since the VORACLE attack makes use of it."

	until [[ $COMPRESSION_ENABLED =~ (y|n) ]]; do
		read -rp"Enable compression? [y/n]: " -e -i n COMPRESSION_ENABLED
	done

	if [[ $COMPRESSION_ENABLED == "y" ]]; then
		echo "Choose which compression algorithm you want to use: (they are ordered by efficiency)"
		echo "   1) LZ4-v2"
		echo "   2) LZ4"
		echo "   3) LZ0"

		until [[ $COMPRESSION_CHOICE =~ ^[1-3]$ ]]; do
			read -rp"Compression algorithm [1-3]: " -e -i 1 COMPRESSION_CHOICE
		done

		case $COMPRESSION_CHOICE in
		  1)
			  COMPRESSION_ALG="lz4-v2"
			  ;;
		  2)
			  COMPRESSION_ALG="lz4"
			  ;;
		  3)
			  COMPRESSION_ALG="lzo"
			  ;;
		esac
	fi

	echo
	echo "Do you want to customize encryption settings?"
	echo "Unless you know what you're doing, you should stick with the default parameters provided by the script."
	echo "Note that whatever you choose, all the choices presented in the script are safe. (Unlike OpenVPN's defaults)"
	echo

	until [[ $CUSTOMIZE_ENC =~ (y|n) ]]; do
		read -rp "Customize encryption settings? [y/n]: " -e -i n CUSTOMIZE_ENC
	done

	if [[ $CUSTOMIZE_ENC == "n" ]]; then
		# Use default, sane and fast parameters
		CIPHER="AES-128-GCM"
		CERT_TYPE="1" # ECDSA
		CERT_CURVE="prime256v1"
		CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
		DH_TYPE="1" # ECDH
		DH_CURVE="prime256v1"
		HMAC_ALG="SHA256"
		TLS_SIG="1" # tls-crypt
	else
		echo
		echo "Choose which cipher you want to use for the data channel:"
		echo "   1) AES-128-GCM (recommended)"
		echo "   2) AES-192-GCM"
		echo "   3) AES-256-GCM"
		echo "   4) AES-128-CBC"
		echo "   5) AES-192-CBC"
		echo "   6) AES-256-CBC"

		until [[ $CIPHER_CHOICE =~ ^[1-6]$ ]]; do
			read -rp "Cipher [1-6]: " -e -i 1 CIPHER_CHOICE
		done

		case $CIPHER_CHOICE in
		  1)
			  CIPHER="AES-128-GCM"
			  ;;
		  2)
			  CIPHER="AES-192-GCM"
			  ;;
		  3)
			  CIPHER="AES-256-GCM"
			  ;;
		  4)
			  CIPHER="AES-128-CBC"
			  ;;
		  5)
			  CIPHER="AES-192-CBC"
			  ;;
		  6)
			  CIPHER="AES-256-CBC"
			  ;;
		esac

		echo
		echo "Choose what kind of certificate you want to use:"
		echo "   1) ECDSA (recommended)"
		echo "   2) RSA"

		until [[ $CERT_TYPE =~ ^[1-2]$ ]]; do
			read -rp"Certificate key type [1-2]: " -e -i 1 CERT_TYPE
		done

		case $CERT_TYPE in
		  1)
			  echo
			  echo "Choose which curve you want to use for the certificate's key:"
			  echo "   1) prime256v1 (recommended)"
			  echo "   2) secp384r1"
			  echo "   3) secp521r1"

			  until [[ $CERT_CURVE_CHOICE =~ ^[1-3]$ ]]; do
				  read -rp"Curve [1-3]: " -e -i 1 CERT_CURVE_CHOICE
			  done

			  case $CERT_CURVE_CHOICE in
			    1)
				    CERT_CURVE="prime256v1"
				    ;;
			    2)
				    CERT_CURVE="secp384r1"
				    ;;
			    3)
				    CERT_CURVE="secp521r1"
				    ;;
			  esac
			  ;;
		  2)
			  echo
			  echo "Choose which size you want to use for the certificate's RSA key:"
			  echo "   1) 2048 bits (recommended)"
			  echo "   2) 3072 bits"
			  echo "   3) 4096 bits"

			  until [[ $RSA_KEY_SIZE_CHOICE =~ ^[1-3]$ ]]; do
				  read -rp "RSA key size [1-3]: " -e -i 1 RSA_KEY_SIZE_CHOICE
			  done
			  case $RSA_KEY_SIZE_CHOICE in
			    1)
				    RSA_KEY_SIZE="2048"
				    ;;
			    2)
				    RSA_KEY_SIZE="3072"
				    ;;
			    3)
				    RSA_KEY_SIZE="4096"
				    ;;
			  esac
			  ;;
		esac

		echo
		echo "Choose which cipher you want to use for the control channel:"

		case $CERT_TYPE in
		  1)
			  echo "   1) ECDHE-ECDSA-AES-128-GCM-SHA256 (recommended)"
			  echo "   2) ECDHE-ECDSA-AES-256-GCM-SHA384"

			  until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
				  read -rp"Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
			  done

			  case $CC_CIPHER_CHOICE in
			    1)
				    CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
				    ;;
			    2)
				    CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384"
				    ;;
			  esac
			  ;;
		  2)
			  echo "   1) ECDHE-RSA-AES-128-GCM-SHA256 (recommended)"
			  echo "   2) ECDHE-RSA-AES-256-GCM-SHA384"

			  until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
				  read -rp"Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
			  done

			  case $CC_CIPHER_CHOICE in
			    1)
				    CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256"
				    ;;
			    2)
				    CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384"
				    ;;
			  esac
			  ;;
		esac

		echo
		echo "Choose what kind of Diffie-Hellman key you want to use:"
		echo "   1) ECDH (recommended)"
		echo "   2) DH"

		until [[ $DH_TYPE =~ [1-2] ]]; do
			read -rp"DH key type [1-2]: " -e -i 1 DH_TYPE
		done

		case $DH_TYPE in
		  1)
			  echo
			  echo "Choose which curve you want to use for the ECDH key:"
			  echo "   1) prime256v1 (recommended)"
			  echo "   2) secp384r1"
			  echo "   3) secp521r1"

			  while [[ $DH_CURVE_CHOICE != "1" && $DH_CURVE_CHOICE != "2" && $DH_CURVE_CHOICE != "3" ]]; do
				  read -rp"Curve [1-3]: " -e -i 1 DH_CURVE_CHOICE
			  done

			  case $DH_CURVE_CHOICE in
			    1)
				    DH_CURVE="prime256v1"
				    ;;
			    2)
				    DH_CURVE="secp384r1"
				    ;;
			    3)
				    DH_CURVE="secp521r1"
				    ;;
			  esac
			  ;;
		  2)
			  echo
			  echo "Choose what size of Diffie-Hellman key you want to use:"
			  echo "   1) 2048 bits (recommended)"
			  echo "   2) 3072 bits"
			  echo "   3) 4096 bits"

			  until [[ $DH_KEY_SIZE_CHOICE =~ ^[1-3]$ ]]; do
				  read -rp "DH key size [1-3]: " -e -i 1 DH_KEY_SIZE_CHOICE
			  done

			  case $DH_KEY_SIZE_CHOICE in
			    1)
				    DH_KEY_SIZE="2048"
				    ;;
			    2)
				    DH_KEY_SIZE="3072"
				    ;;
			    3)
				    DH_KEY_SIZE="4096"
				    ;;
			  esac
			  ;;
		esac
		echo

		# The "auth" options behaves differently with AEAD ciphers
		if [[ $CIPHER =~ CBC$ ]]; then
			echo "The digest algorithm authenticates data channel packets and tls-auth packets from the control channel."
		elif [[ $CIPHER =~ GCM$ ]]; then
			echo "The digest algorithm authenticates tls-auth packets from the control channel."
		fi

		echo "Which digest algorithm do you want to use for HMAC?"
		echo "   1) SHA-256 (recommended)"
		echo "   2) SHA-384"
		echo "   3) SHA-512"

		until [[ $HMAC_ALG_CHOICE =~ ^[1-3]$ ]]; do
			read -rp "Digest algorithm [1-3]: " -e -i 1 HMAC_ALG_CHOICE
		done

		case $HMAC_ALG_CHOICE in
		  1)
			  HMAC_ALG="SHA256"
			  ;;
		  2)
			  HMAC_ALG="SHA384"
			  ;;
		  3)
			  HMAC_ALG="SHA512"
			  ;;
		esac

		echo
		echo "You can add an additional layer of security to the control channel with tls-auth and tls-crypt"
		echo "tls-auth authenticates the packets, while tls-crypt authenticate and encrypt them."
		echo "   1) tls-crypt (recommended)"
		echo "   2) tls-auth"

		until [[ $TLS_SIG =~ [1-2] ]]; do
			read -rp "Control channel additional security mechanism [1-2]: " -e -i 1 TLS_SIG
		done
	fi

	echo
	echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now."
	echo "You will be able to generate a client at the end of the installation."

	APPROVE_INSTALL=${APPROVE_INSTALL:-n}

	if [[ $APPROVE_INSTALL =~ n ]]; then
		read -n1 -r -p "Press any key to continue..."
	fi
}

function installOpenVPN() {
	if [[ $AUTO_INSTALL == "y" ]]; then
		# Set default choices so that no questions will be asked.
		HOME_DIR=${HOME_DIR:-/root}
		APPROVE_INSTALL=${APPROVE_INSTALL:-y}
		APPROVE_IP=${APPROVE_IP:-y}
		SERVER_NETWORK_PREFIX=${SERVER_NETWORK_PREFIX:-10.8.0.0}
		SERVER_NETWORK_MASK=${SERVER_NETWORK_MASK:-24}
		PORT_CHOICE=${PORT_CHOICE:-1}
		PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
		DNS=${DNS:-1}
		COMPRESSION_ENABLED=${COMPRESSION_ENABLED:-n}
		CUSTOMIZE_ENC=${CUSTOMIZE_ENC:-n}
		CLIENT=${CLIENT:-client}
		PASS=${PASS:-1}
		CONTINUE=${CONTINUE:-y}

		# Behind NAT, we'll default to the publicly reachable IPv4/IPv6.
    if ! PUBLIC_IP=$(curl -f --retry 5 --retry-connrefused -4 https://ip.seeip.org); then
      PUBLIC_IP=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
    fi

		ENDPOINT=${ENDPOINT:-$PUBLIC_IP}
	fi

	# Run setup questions first, and set other variables if auto-install
	installQuestions

	# Get the "public" interface from the default route
	NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

	# $NIC can not be empty for script rm-openvpn-rules.sh
	if [[ -z $NIC ]]; then
		echo
		echo "Can not detect public interface."
		echo "This needs for setup MASQUERADE."

		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done

		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
	fi

	# If OpenVPN isn't installed yet, install it. This script is more-or-less
	# idempotent on multiple runs, but will only install OpenVPN from upstream
	# the first time.

	if [[ ! -e /etc/openvpn/server.conf ]]; then
		if [[ $OS =~ (debian|ubuntu) ]]; then
			apt-get update
			apt-get -y install ca-certificates gnupg

			# We add the OpenVPN repo to get the latest version.
			if [[ $VERSION_ID == "16.04" ]]; then
				echo "deb http://build.openvpn.net/debian/openvpn/stable xenial main" > /etc/apt/sources.list.d/openvpn.list
				wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
				apt-get update
			fi

			# Ubuntu > 16.04 and Debian > 8 have OpenVPN >= 2.4 without the need of a third party repository.
			apt-get install -y openvpn iptables openssl wget ca-certificates curl
		elif [[ $OS == 'centos' ]]; then
			yum install -y epel-release
			yum install -y openvpn iptables openssl wget ca-certificates curl tar 'policycoreutils-python*'
		elif [[ $OS == 'oracle' ]]; then
			yum install -y oracle-epel-release-el8
			yum-config-manager --enable ol8_developer_EPEL
			yum install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python-utils
		elif [[ $OS == 'amzn' ]]; then
			amazon-linux-extras install -y epel
			yum install -y openvpn iptables openssl wget ca-certificates curl
		elif [[ $OS == 'fedora' ]]; then
			dnf install -y openvpn iptables openssl wget ca-certificates curl policycoreutils-python-utils
		elif [[ $OS == 'arch' ]]; then
			# Install required dependencies and upgrade the system
			pacman --needed --noconfirm -Syu openvpn iptables openssl wget ca-certificates curl
		fi
		# An old version of easy-rsa was available by default in some openvpn packages
		if [[ -d /etc/openvpn/easy-rsa/ ]]; then
			rm -rf /etc/openvpn/easy-rsa/
		fi
	fi

	# Find out if the machine uses nogroup or nobody for the permissionless group
	if grep -qs "^nogroup:" /etc/group; then
		NOGROUP=nogroup
	else
		NOGROUP=nobody
	fi

	# Install the latest version of easy-rsa from source, if not already installed.
	if [[ ! -d /etc/openvpn/easy-rsa/ ]]; then
		local version="3.1.2"
		wget -O ~/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-${version}.tgz
		mkdir -p /etc/openvpn/easy-rsa
		tar xzf ~/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa
		rm -f ~/easy-rsa.tgz
		cd /etc/openvpn/easy-rsa/ || return

		case $CERT_TYPE in
		  1)
			  echo "set_var EASYRSA_ALGO ec" > vars
			  echo "set_var EASYRSA_CURVE $CERT_CURVE" >> vars
			  ;;
		  2)
			  echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" > vars
			  ;;
		esac

		# Generate a random, alphanumeric identifier of 16 characters for CN and one for server name
		SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"

		echo "$SERVER_CN" >SERVER_CN_GENERATED

		SERVER_NAME="server_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"

		echo "$SERVER_NAME" >SERVER_NAME_GENERATED

		# Create the PKI, set up the CA, the DH params and the server certificate
		./easyrsa init-pki
		./easyrsa --batch --req-cn="$SERVER_CN" build-ca nopass

		if [[ $DH_TYPE == "2" ]]; then
			# ECDH keys are generated on-the-fly so we don't need to generate them beforehand
			openssl dhparam -out dh.pem $DH_KEY_SIZE
		fi

		./easyrsa --batch build-server-full "$SERVER_NAME" nopass

		EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

		case $TLS_SIG in
		  1)
			  # Generate tls-crypt key
			  openvpn --genkey --secret /etc/openvpn/tls-crypt.key
			  ;;
		  2)
			  # Generate tls-auth key
			  openvpn --genkey --secret /etc/openvpn/tls-auth.key
			  ;;
		esac
	else
		# If easy-rsa is already installed, grab the generated SERVER_NAME
		# for client configs
		cd /etc/openvpn/easy-rsa/ || return

		SERVER_NAME=$(cat SERVER_NAME_GENERATED)
	fi

	# Move all the generated files
	cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn

	if [[ $DH_TYPE == "2" ]]; then
		cp dh.pem /etc/openvpn
	fi

	# Make cert revocation list readable for non-root
	chmod 644 /etc/openvpn/crl.pem

	# Generate server.conf
	echo "port $PORT" > /etc/openvpn/server.conf
  echo "proto $PROTOCOL" >> /etc/openvpn/server.conf
	echo "dev tun" >> /etc/openvpn/server.conf
  echo "user nobody" >> /etc/openvpn/server.conf
  echo "group $NOGROUP" >> /etc/openvpn/server.conf
  echo "persist-key" >> /etc/openvpn/server.conf
  echo "persist-tun" >> /etc/openvpn/server.conf
  echo "keepalive 10 120" >> /etc/openvpn/server.conf
  echo "topology subnet" >> /etc/openvpn/server.conf
  echo "server $SERVER_NETWORK_PREFIX $(cidrToNetmask $SERVER_NETWORK_MASK)" >> /etc/openvpn/server.conf
  echo "ifconfig-pool-persist ipp.txt" >> /etc/openvpn/server.conf

	# DNS resolvers
	case $DNS in
	  1)
	    # Current system resolvers
		  # Locate the proper resolv.conf
		  # Needed for systems running systemd-resolved
		  if grep -q "127.0.0.53" "/etc/resolv.conf"; then
			  RESOLVCONF='/run/systemd/resolve/resolv.conf'
		  else
			  RESOLVCONF='/etc/resolv.conf'
		  fi

		  # Obtain the resolvers from resolv.conf and use them for OpenVPN
		  sed -ne 's/^nameserver[[:space:]]\+\([^[:space:]]\+\).*$/\1/p' $RESOLVCONF | while read -r line; do
			  if [[ $line =~ ^[0-9.]*$ ]]; then
				  echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf
			  fi
		  done
		  ;;
	  2) # Cloudflare
		  echo 'push "dhcp-option DNS 1.0.0.1"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 1.1.1.1"' >> /etc/openvpn/server.conf
		  ;;
	  3) # Quad9
		  echo 'push "dhcp-option DNS 9.9.9.9"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 149.112.112.112"' >> /etc/openvpn/server.conf
		  ;;
	  4) # Quad9 uncensored
		  echo 'push "dhcp-option DNS 9.9.9.10"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 149.112.112.10"' >> /etc/openvpn/server.conf
		  ;;
	  5) # FDN
		  echo 'push "dhcp-option DNS 80.67.169.40"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 80.67.169.12"' >> /etc/openvpn/server.conf
		  ;;
	  6) # DNS.WATCH
		  echo 'push "dhcp-option DNS 84.200.69.80"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 84.200.70.40"' >> /etc/openvpn/server.conf
		  ;;
	  7) # OpenDNS
		  echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server.conf
		  ;;
	  8) # Google
		  echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server.conf
		  ;;
	  9) # Yandex Basic
		  echo 'push "dhcp-option DNS 77.88.8.8"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 77.88.8.1"' >> /etc/openvpn/server.conf
		  ;;
	  10) # AdGuard DNS
		  echo 'push "dhcp-option DNS 94.140.14.14"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 94.140.15.15"' >> /etc/openvpn/server.conf
		  ;;
	  11) # NextDNS
		  echo 'push "dhcp-option DNS 45.90.28.167"' >> /etc/openvpn/server.conf
		  echo 'push "dhcp-option DNS 45.90.30.167"' >> /etc/openvpn/server.conf
		  ;;
	  12) # Custom DNS
		  echo "push \"dhcp-option DNS $DNS1\"" >> /etc/openvpn/server.conf

		  if [[ $DNS2 != "" ]]; then
			  echo "push \"dhcp-option DNS $DNS2\"" >> /etc/openvpn/server.conf
		  fi
		  ;;
	esac

	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf

	if [[ $COMPRESSION_ENABLED == "y" ]]; then
		echo "compress $COMPRESSION_ALG" >> /etc/openvpn/server.conf
	fi

	if [[ $DH_TYPE == "1" ]]; then
		echo "dh none" >> /etc/openvpn/server.conf
		echo "ecdh-curve $DH_CURVE" >> /etc/openvpn/server.conf
	elif [[ $DH_TYPE == "2" ]]; then
		echo "dh dh.pem" >> /etc/openvpn/server.conf
	fi

	case $TLS_SIG in
	  1)
		  echo "tls-crypt tls-crypt.key" >> /etc/openvpn/server.conf
		  ;;
	  2)
		  echo "tls-auth tls-auth.key 0" >> /etc/openvpn/server.conf
		  ;;
	esac

	echo "crl-verify crl.pem" >> /etc/openvpn/server.conf
  echo "ca ca.crt" >> /etc/openvpn/server.conf
  echo "cert $SERVER_NAME.crt" >> /etc/openvpn/server.conf
  echo "key $SERVER_NAME.key" >> /etc/openvpn/server.conf
  echo "auth $HMAC_ALG" >> /etc/openvpn/server.conf
  echo "cipher $CIPHER" >> /etc/openvpn/server.conf
  echo "ncp-ciphers $CIPHER" >> /etc/openvpn/server.conf
  echo "tls-server" >> /etc/openvpn/server.conf
  echo "tls-version-min 1.2" >> /etc/openvpn/server.conf
  echo "tls-cipher $CC_CIPHER" >> /etc/openvpn/server.conf
  echo "client-config-dir /etc/openvpn/ccd" >> /etc/openvpn/server.conf
  echo "status /var/log/openvpn/status.log" >> /etc/openvpn/server.conf
  echo "verb 3" >> /etc/openvpn/server.conf

	# Create client-config-dir dir
	mkdir -p /etc/openvpn/ccd
	# Create log dir
	mkdir -p /var/log/openvpn

	# Enable routing
	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn.conf

	# Apply sysctl rules
	sysctl --system

	# If SELinux is enabled and a custom port was selected, we need this
	if hash sestatus 2> /dev/null; then
		if sestatus | grep "Current mode" | grep -qs "enforcing"; then
			if [[ $PORT != '1194' ]]; then
				semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT"
			fi
		fi
	fi

	# Finally, restart and enable OpenVPN
	if [[ $OS == 'arch' || $OS == 'fedora' || $OS == 'centos' || $OS == 'oracle' ]]; then
		# Don't modify package-provided service
		cp /usr/lib/systemd/system/openvpn-server@.service /etc/systemd/system/openvpn-server@.service

		# Workaround to fix OpenVPN service on OpenVZ
		sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn-server@.service

		# Another workaround to keep using /etc/openvpn/
		sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn-server@.service

		systemctl daemon-reload
		systemctl enable openvpn-server@server
		systemctl restart openvpn-server@server
	elif [[ $OS == "ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
		# On Ubuntu 16.04, we use the package from the OpenVPN repo
		# This package uses a sysvinit service
		systemctl enable openvpn
		systemctl start openvpn
	else
		# Don't modify package-provided service
		cp /lib/systemd/system/openvpn\@.service /etc/systemd/system/openvpn\@.service

		# Workaround to fix OpenVPN service on OpenVZ
		sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn\@.service

		# Another workaround to keep using /etc/openvpn/
		sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn\@.service

		systemctl daemon-reload
		systemctl enable openvpn@server
		systemctl restart openvpn@server
	fi

	# Add iptables rules in two scripts
	mkdir -p /etc/iptables

	# Script to add rules
	echo "#!/bin/sh" > /etc/iptables/add-openvpn-rules.sh
  echo "iptables -t nat -I POSTROUTING 1 -s $SERVER_NETWORK_PREFIX/$SERVER_NETWORK_MASK -o $NIC -j MASQUERADE" >> /etc/iptables/add-openvpn-rules.sh
  echo "iptables -I INPUT 1 -i tun0 -j ACCEPT" >> /etc/iptables/add-openvpn-rules.sh
  echo "iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT" >> /etc/iptables/add-openvpn-rules.sh
  echo "iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT" >> /etc/iptables/add-openvpn-rules.sh
  echo "iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >> /etc/iptables/add-openvpn-rules.sh

	# Script to remove rules
	echo "#!/bin/sh" > /etc/iptables/rm-openvpn-rules.sh
  echo "iptables -t nat -D POSTROUTING -s $SERVER_NETWORK_PREFIX/$SERVER_NETWORK_MASK -o $NIC -j MASQUERADE" >> /etc/iptables/rm-openvpn-rules.sh
  echo "iptables -D INPUT -i tun0 -j ACCEPT" >> /etc/iptables/rm-openvpn-rules.sh
  echo "iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT" >> /etc/iptables/rm-openvpn-rules.sh
  echo "iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT" >> /etc/iptables/rm-openvpn-rules.sh
  echo "iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >> /etc/iptables/rm-openvpn-rules.sh

	chmod +x /etc/iptables/add-openvpn-rules.sh
	chmod +x /etc/iptables/rm-openvpn-rules.sh

	# Handle the rules via a systemd script
	echo "[Unit]" > /etc/systemd/system/iptables-openvpn.service
  echo "Description=iptables rules for OpenVPN" >> /etc/systemd/system/iptables-openvpn.service
  echo "Before=network-online.target" >> /etc/systemd/system/iptables-openvpn.service
  echo "Wants=network-online.target" >> /etc/systemd/system/iptables-openvpn.service
  echo >> /etc/systemd/system/iptables-openvpn.service
  echo "[Service]" >> /etc/systemd/system/iptables-openvpn.service
  echo "Type=oneshot" >> /etc/systemd/system/iptables-openvpn.service
  echo "ExecStart=/etc/iptables/add-openvpn-rules.sh" >> /etc/systemd/system/iptables-openvpn.service
  echo "ExecStop=/etc/iptables/rm-openvpn-rules.sh" >> /etc/systemd/system/iptables-openvpn.service
  echo "RemainAfterExit=yes" >> /etc/systemd/system/iptables-openvpn.service
  echo >> /etc/systemd/system/iptables-openvpn.service
  echo "[Install]" >> /etc/systemd/system/iptables-openvpn.service
  echo "WantedBy=multi-user.target" >> /etc/systemd/system/iptables-openvpn.service

	# Enable service and apply rules
	systemctl daemon-reload
	systemctl enable iptables-openvpn
	systemctl start iptables-openvpn

	# If the server is behind a NAT, use the correct IP address for the clients to connect to
	if [[ $ENDPOINT != "" ]]; then
		IP=$ENDPOINT
	fi

	# client-template.txt is created so we have a template to add further users later
	echo "client" > /etc/openvpn/client-template.txt
	
	if [[ $PROTOCOL == 'udp' ]]; then
		echo "proto udp" >> /etc/openvpn/client-template.txt
		echo "explicit-exit-notify" >> /etc/openvpn/client-template.txt
	elif [[ $PROTOCOL == 'tcp' ]]; then
		echo "proto tcp-client" >> /etc/openvpn/client-template.txt
	fi

	echo "remote $IP $PORT" >> /etc/openvpn/client-template.txt
  echo "dev tun" >> /etc/openvpn/client-template.txt
  echo "resolv-retry infinite" >> /etc/openvpn/client-template.txt
  echo "nobind" >> /etc/openvpn/client-template.txt
  echo "persist-key" >> /etc/openvpn/client-template.txt
  echo "persist-tun" >> /etc/openvpn/client-template.txt
  echo "remote-cert-tls server" >> /etc/openvpn/client-template.txt
  echo "verify-x509-name $SERVER_NAME name" >> /etc/openvpn/client-template.txt
  echo "auth $HMAC_ALG" >> /etc/openvpn/client-template.txt
  echo "auth-nocache" >> /etc/openvpn/client-template.txt
  echo "cipher $CIPHER" >> /etc/openvpn/client-template.txt
  echo "tls-client" >> /etc/openvpn/client-template.txt
  echo "tls-version-min 1.2" >> /etc/openvpn/client-template.txt
  echo "tls-cipher $CC_CIPHER" >> /etc/openvpn/client-template.txt
  echo "ignore-unknown-option block-outside-dns" >> /etc/openvpn/client-template.txt
  echo "setenv opt block-outside-dns # Prevent Windows 10 DNS leak" >> /etc/openvpn/client-template.txt
  echo "verb 3" >> /etc/openvpn/client-template.txt

	if [[ $COMPRESSION_ENABLED == "y" ]]; then
		echo "compress $COMPRESSION_ALG" >> /etc/openvpn/client-template.txt
	fi

	# Generate the custom client.ovpn
	newClient
	echo "If you want to add more clients, you simply need to run this script another time!"
}

function newClient() {
	echo
	echo "Tell me a name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash."

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "Client name: " -e CLIENT
	done

	echo
	echo "Do you want to protect the configuration file with a password?"
	echo "(e.g. encrypt the private key with a password)"
	echo "   1) Add a passwordless client"
	echo "   2) Use a password for the client"

	until [[ $PASS =~ ^[1-2]$ ]]; do
		read -rp "Select an option [1-2]: " -e -i 1 PASS
	done

	CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")

	if [[ $CLIENTEXISTS == '1' ]]; then
		echo
		echo "The specified client CN was already found in easy-rsa, please choose another name."

		exit
	else
		cd /etc/openvpn/easy-rsa/ || return

		case $PASS in
		  1)
			  ./easyrsa --batch build-client-full "$CLIENT" nopass
			  ;;
		  2)
			  echo "⚠️ You will be asked for the client password below ⚠️"
			  ./easyrsa --batch build-client-full "$CLIENT"
			  ;;
		esac

		echo "Client $CLIENT added."
	fi

	# Determine if we use tls-auth or tls-crypt
	if grep -qs "^tls-crypt" /etc/openvpn/server.conf; then
		TLS_SIG="1"
	elif grep -qs "^tls-auth" /etc/openvpn/server.conf; then
		TLS_SIG="2"
	fi

	ETC_DIR="$HOME_DIR"/etc

	mkdir -p "$ETC_DIR"

	# Generates the custom client.ovpn
	cp /etc/openvpn/client-template.txt "$ETC_DIR/$CLIENT.ovpn"
	{
		echo "<ca>"
		cat "/etc/openvpn/easy-rsa/pki/ca.crt"
		echo "</ca>"

		echo "<cert>"
		awk '/BEGIN/,/END CERTIFICATE/' "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"
		echo "</cert>"

		echo "<key>"
		cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"
		echo "</key>"

		case $TLS_SIG in
		  1)
			  echo "<tls-crypt>"
			  cat /etc/openvpn/tls-crypt.key
			  echo "</tls-crypt>"
			  ;;
		  2)
			  echo "key-direction 1"
			  echo "<tls-auth>"
			  cat /etc/openvpn/tls-auth.key
			  echo "</tls-auth>"
			  ;;
		esac

    echo "pull-filter ignore redirect-gateway"
    echo "route-nopull"
    echo "route $SERVER_NETWORK_PREFIX $(cidrToNetmask $SERVER_NETWORK_MASK)"

    SUBNET1_RANGE=$(route -n | grep eth1 | awk '{print $1}')
    SUBNET1_NETMASK=$(route -n | grep eth1 | awk '{print $3}')

    SUBNET2_RANGE=$(route -n | grep eth2 | awk '{print $1}')
    SUBNET2_NETMASK=$(route -n | grep eth2 | awk '{print $3}')

    SUBNET3_RANGE=$(route -n | grep eth3 | awk '{print $1}')
    SUBNET3_NETMASK=$(route -n | grep eth3 | awk '{print $3}')

    if [ -n "$SUBNET1_RANGE" ] || [ -n "$SUBNET2_RANGE" ] || [ -n "$SUBNET3_RANGE" ]; then
      if [ -n "$SUBNET1_RANGE" ]; then
        echo "route $SUBNET1_RANGE $SUBNET1_NETMASK"
      fi

      if [ -n "$SUBNET2_RANGE" ]; then
        echo "route $SUBNET2_RANGE $SUBNET2_NETMASK"
      fi

      if [ -n "$SUBNET3_RANGE" ]; then
        echo "route $SUBNET3_RANGE $SUBNET3_NETMASK"
      fi
    fi
	} >> "$ETC_DIR/$CLIENT.ovpn"

	echo
	echo "The configuration file has been written to $ETC_DIR/$CLIENT.ovpn."
	echo "Download the .ovpn file and import it in your OpenVPN client."

	exit 0
}

function revokeClient() {
  ETC_DIR="$HOME_DIR"/etc
	NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")

	if [[ $NUMBEROFCLIENTS == '0' ]]; then
		echo
		echo "You have no existing clients!"

		exit 1
	fi

	echo
	echo "Select the existing client certificate you want to revoke"
	tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '

	until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
		if [[ $CLIENTNUMBER == '1' ]]; then
			read -rp "Select one client [1]: " CLIENTNUMBER
		else
			read -rp "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
		fi
	done

	CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)

	cd /etc/openvpn/easy-rsa/ || return
	./easyrsa --batch revoke "$CLIENT"

	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

	rm -f /etc/openvpn/crl.pem
	cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
	chmod 644 /etc/openvpn/crl.pem
	find /home/ -maxdepth 2 -name "$CLIENT.ovpn" -delete
	rm -f "$ETC_DIR/$CLIENT.ovpn"
	sed -i "/^$CLIENT,.*/d" /etc/openvpn/ipp.txt
	cp /etc/openvpn/easy-rsa/pki/index.txt{,.bk}

	echo
	echo "Certificate for client $CLIENT revoked."
}

function removeOpenVPN() {
  ETC_DIR="$HOME_DIR"/etc

	echo
	read -rp "Do you really want to remove OpenVPN? [y/n]: " -e -i n REMOVE

	if [[ $REMOVE == 'y' ]]; then
		# Get OpenVPN port from the configuration
		PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
		PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)

		# Stop OpenVPN
		if [[ $OS =~ (fedora|arch|centos|oracle) ]]; then
			systemctl disable openvpn-server@server
			systemctl stop openvpn-server@server

			# Remove customised service
			rm /etc/systemd/system/openvpn-server@.service
		elif [[ $OS == "ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
			systemctl disable openvpn
			systemctl stop openvpn
		else
			systemctl disable openvpn@server
			systemctl stop openvpn@server

			# Remove customised service
			rm /etc/systemd/system/openvpn\@.service
		fi

		# Remove the iptables rules related to the script
		systemctl stop iptables-openvpn

		# Cleanup
		systemctl disable iptables-openvpn
		rm /etc/systemd/system/iptables-openvpn.service
		systemctl daemon-reload
		rm /etc/iptables/add-openvpn-rules.sh
		rm /etc/iptables/rm-openvpn-rules.sh

		# SELinux
		if hash sestatus 2> /dev/null; then
			if sestatus | grep "Current mode" | grep -qs "enforcing"; then
				if [[ $PORT != '1194' ]]; then
					semanage port -d -t openvpn_port_t -p "$PROTOCOL" "$PORT"
				fi
			fi
		fi

		if [[ $OS =~ (debian|ubuntu) ]]; then
			apt-get remove --purge -y openvpn
			if [[ -e /etc/apt/sources.list.d/openvpn.list ]]; then
				rm /etc/apt/sources.list.d/openvpn.list
				apt-get update
			fi
		elif [[ $OS == 'arch' ]]; then
			pacman --noconfirm -R openvpn
		elif [[ $OS =~ (centos|amzn|oracle) ]]; then
			yum remove -y openvpn
		elif [[ $OS == 'fedora' ]]; then
			dnf remove -y openvpn
		fi

		# Cleanup
		find "$ETC_DIR" -maxdepth 2 -name "*.ovpn" -delete
		find /root/ -maxdepth 1 -name "*.ovpn" -delete
		rm -rf /etc/openvpn
		rm -rf /usr/share/doc/openvpn*
		rm -f /etc/sysctl.d/99-openvpn.conf
		rm -rf /var/log/openvpn

    echo
		echo "OpenVPN removed!"
	else
		echo
		echo "Removal aborted!"
	fi
}

function manageMenu() {
	echo "Welcome to OpenVPN-install!"
	echo
	echo "It looks like OpenVPN is already installed."
	echo
	echo "What do you want to do?"
	echo "   1) Add a new user"
	echo "   2) Revoke existing user"
	echo "   3) Remove OpenVPN"
	echo "   4) Exit"

	until [[ $MENU_OPTION =~ ^[1-4]$ ]]; do
		read -rp "Select an option [1-4]: " MENU_OPTION
	done

	case $MENU_OPTION in
	  1)
		  newClient
		  ;;
	  2)
		  revokeClient
		  ;;
	  3)
		  removeOpenVPN
		  ;;
	  4)
		  exit 0
		  ;;
	esac
}

# Check for root, TUN, OS...
initialCheck

# Check if OpenVPN is already installed
if [[ -e /etc/openvpn/server.conf && $AUTO_INSTALL != "y" ]]; then
	manageMenu
else
	installOpenVPN
fi