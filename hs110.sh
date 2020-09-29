#!/bin/bash

if [ "$1" = "debug" ] ; then DEBUG=1 ; else DEBUG=0 ; fi

BC=`which bc`
DATE=`which date`
JQ=`which jq`
WGET=`which wget`
TIMEOUT=`which timeout`
GREP=`which grep`
CURL=`which curl`
NETSTAT=`which netstat`
PIDOF=`which pidof`

# Exit if still runs
if [ $($PIDOF -x "$0" | wc -w) -ne 2 ] ; then exit ; fi

SLACKCHANNEL=YOU_SLACK_CHANNEL_NAME
SLACK_HOOK_URL=https://hooks.slack.com/services/YOUR/SERVICE/CODE

# Brutto Strompreis in ct/kWh mit PUNKT als Trenner
STROMPREIS=30.59
# Sekunden der Stoperkennung
STOPSEC=180
MYPATH=/home/pi/SlackMySteckdose
RAMDISK=/ramdisk
TPLINK=$MYPATH/tplink-smartplug.py
OWNIP=$(/sbin/ifconfig -a | $GREP "inet .*netmask.*broadcast" | $GREP -v "127.0" | head -1 | awk '{print $2}')
PREFIX=$(echo $OWNIP | cut -d"." -f1-3)
GW=$($NETSTAT -rn | $GREP default.*${PREFIX} | awk '{print $2}' | head -1)


if [ ! -d $RAMDISK ] ; then echo "NO RAMDISK - exiting ..." ; exit ; fi

# Dieses Gerät ist
touch ${RAMDISK}/raspi_$(/sbin/ifconfig -a | $GREP "ether " | awk '{print $2}' | head -1)
OWNMAC=$(ls -1 ${RAMDISK}/raspi* | cut -d "_" -f2)
if [ ! $OWNMAC ] ; then echo "NO own MAC detectet - exiting ..." ; exit ; fi

# Finde alle Steckdosen im Netz
# Beispiel DHCP Bereich ist von .20 bis .200
for IP in {20..200} ; do
	if [ $DEBUG -eq 1 ] ; then echo -n "." ; fi

	/bin/nc -w 1 -z ${PREFIX}.${IP} 9999 2>/dev/null || continue
	GOTCHA="$GOTCHA ${IP} "

	if [ $DEBUG -eq 1 ] ; then echo -n "[${IP}]" ; fi
done
if [ $DEBUG -eq 1 ] ; then echo ; echo "Gotcha: $GOTCHA"  ; fi

# Lege Hilfsdateien unter $RAMDISK an
IP=""
for IP in $GOTCHA ; do

	JSON=$(${TPLINK} -t ${PREFIX}.${IP} -c info | $GREP ^Received | /usr/bin/cut -d ":" -f2-)

	if [ "$(echo $JSON | jq -r '.system.get_sysinfo.model')" == "HS110(EU)" ] ; then

		MAC=$(echo $JSON | jq -r '.system.get_sysinfo.mac')
		ALIAS=$(echo $JSON | jq -r '.system.get_sysinfo.alias')
		
		touch ${RAMDISK}/HS110_${MAC}_${PREFIX}.${IP}
		if [ $DEBUG -eq 1 ] ; then echo "touch ${RAMDISK}/HS110_${MAC}_${PREFIX}.${IP}" ; fi

	fi
done


# Aufräumen
rm -rf ${RAMDISK}/ignore_* ${RAMDISK}/start_* ${RAMDISK}/stop_*

# Endlosschleife
# Endlosschleife
# Endlosschleife
while true ; do
IP=""

# Ausgelesen um
ZEIT=$($DATE +%s)

# Päuschen erst nach dem ersten Durchlauf
# Net wundern, wird erst am Ende des ersten Durchlaufes gesetzt.
$SLEEP

# Abfrage aller gefundenen Dosen
for IP in $(ls -1 ${RAMDISK}/HS110* | cut -d "_" -f3) ; do
MAC=$(ls -1 ${RAMDISK}/HS110*${IP} | cut -d"_" -f2)

# Script-Sprung, wenn die Dose kurzzeitig mal nicht erreichbar ist
$TIMEOUT 1 bash -c "cat < /dev/null > /dev/tcp/${IP}/9999 2> /dev/null" || continue

# Aktuelle Steckdose auslesen
EMETER=$($TPLINK -t $IP -c emeter | $GREP ^Received | cut -d ":" -f2-)
POWER=$(echo $EMETER | $JQ '.emeter.get_realtime.power' | cut -d "." -f1)

# continue loop if device is on ignore list
if [ -f ${RAMDISK}/ignore_${MAC} ] ; then if [ $DEBUG -eq 1 ] ; then echo "# --- $MAC is on ignore list" ; fi ; continue ; fi 
if [ -f ${MYPATH}/ignore_${MAC} ] ; then if [ $DEBUG -eq 1 ] ; then echo "# --- $MAC is on ignore list" ; fi ; continue ; fi

# Unter 5 Watt-Erkennung
if [ $POWER -lt 5 ] ; then
	if [ $DEBUG -eq 1 ] ; then echo "# --- Kleiner 5 Watt bei $MAC" ; fi
	# Lege STOP Datei an, wenn es noch keine gibt, aber es eine START Datei gibt
	if [ $(ls -1 ${MYPATH}/stop_${MAC}_* 2>/dev/null | wc -l) -eq 0 ] && [ $(ls -1 ${MYPATH}/start_${MAC}_* 2>/dev/null | wc -l) -ne 0 ] ; then 
		if [ $DEBUG -eq 1 ] ; then
			echo "# --- Anlegen stop_${MAC}_${ZEIT}_$(echo $EMETER | $JQ -r '.emeter.get_realtime.total')"
		fi
		touch ${MYPATH}/stop_${MAC}_${ZEIT}_$(echo $EMETER | $JQ -r '.emeter.get_realtime.total')
	fi

	# Checke DELTA, wenn es eine START und eine STOP Datei gibt
	if [ $(ls -1 ${MYPATH}/start_${MAC}_* 2>/dev/null | wc -l) -ne 0 ] && [ $(ls -1 ${MYPATH}/stop_${MAC}_* 2>/dev/null | wc -l) -ne 0 ] ; then
		SINCE=$(ls -1 ${MYPATH}/stop_${MAC}_* | cut -d"_" -f3)
		DELTA=$(( $ZEIT - $SINCE )) 
		if [ $DEBUG -eq 1 ] ; then
			echo "# --- Zeit:  $ZEIT"
			echo "# --- Since: $SINCE"
			echo "# --- Delta: $DELTA (aus seit)"
		fi
		# Ausschalteerkennung
		# Ausschalteerkennung
		# Ausschalteerkennung
		# Ausschalteerkennung
		# Ausschalteerkennung
		# Ausschalteerkennung
		if [ $DELTA -gt $STOPSEC ] ; then 
			INFO=$($TPLINK -t $IP -c info | $GREP ^Received | cut -d ":" -f2-)
			RUN=$(( $SINCE - $(ls -1 ${MYPATH}/start_${MAC}_* | cut -d"_" -f3) ))
			KWSTART=$(ls -1 ${MYPATH}/start_${MAC}_* | cut -d"_" -f4)
			KWSTOP=$(ls -1 ${MYPATH}/stop_${MAC}_* | cut -d"_" -f4)
			VERBRAUCH=$($BC <<< "scale=0 ; ($KWSTOP - $KWSTART) * 1000 / 1")
			KOSTEN=$($BC <<< "scale=0 ; ($KWSTOP - $KWSTART) * ${STROMPREIS}" | sed 's:\.:,:')
			EMOJI=":zap:"
			DEVICE=$(echo $INFO | $JQ -r '.system.get_sysinfo.alias')
			if [ "$DEVICE" == "BurgWaschmaschine" ] ; then EMOJI=":sweat_drops:" ; fi
			if [ "$DEVICE" == "BurgTrockner" ] ; then EMOJI=":tornado:" ; fi
			if [ "$DEVICE" == "BurgWasserkocher" ] ; then EMOJI=":fire:" ; fi
			MELDUNG="Das Gerät $DEVICE wurde ausgeschaltet, lief $RUN Sekunden und hat $VERBRAUCH Wh verbraucht. Das sind knapp ${KOSTEN} ct."
			if [ $DEBUG -eq 1 ] ; then echo "# --- SLACK: $MELDUNG"; fi

			# Notify detections only above 5Wh
			if [ $VERBRAUCH -gt 5 ] ; then
			SLACK=""
			SLACK=$($CURL --silent -X POST --data-urlencode "payload={\"channel\": \"${SLACKCHANNEL}\", \"username\": \"SmartBurg\", \"text\": \"${MELDUNG}\", \"icon_emoji\": \"${EMOJI}\"}" $SLACK_HOOK_URL)
			fi

			if [ "$SLACK" == "ok" ] ; then
				rm -f ${MYPATH}/start_${MAC}_*
				rm -f ${MYPATH}/stop_${MAC}_*
				echo "$CURL --silent -X POST --data-urlencode \"payload={\"channel\": \"${SLACKCHANNEL}\", \"username\": \"SmartBurg\", \"text\": \"${MELDUNG}\", \"icon_emoji\": \"${EMOJI}\"}\" $SLACK_HOOK_URL"
			fi
		fi
	fi
	continue
fi

INFO=$($TPLINK -t $IP -c info | $GREP ^Received | cut -d ":" -f2-)
MAC=$(echo $INFO | $JQ -r '.system.get_sysinfo.mac')

# Einschalterkennung
# Einschalterkennung
# Einschalterkennung
# Einschalterkennung
# Einschalterkennung
# Wenn noch keine start_Datei existiert, ...
if [ $(ls -1 ${MYPATH}/start_${MAC}_* 2>/dev/null | wc -l) -eq 0 ] ; then
	EMOJI=":zap:"
	DEVICE=$(echo $INFO | $JQ -r '.system.get_sysinfo.alias')
	if [ "$DEVICE" == "BurgWaschmaschine" ] ; then EMOJI=":sweat_drops:" ; fi
	if [ "$DEVICE" == "BurgTrockner" ] ; then EMOJI=":tornado:" ; fi
	if [ "$DEVICE" == "BurgWasserkocher" ] ; then EMOJI=":fire:" ; fi
	MELDUNG="Das Gerät $DEVICE wurde eingeschaltet"
	if [ $DEBUG -eq 1 ] ; then
		echo "# --- Anlegen start_${MAC}_${ZEIT}_$(echo $EMETER | $JQ -r '.emeter.get_realtime.total')"
		echo "# --- SLACK: $MELDUNG"
	fi
	touch ${MYPATH}/start_${MAC}_${ZEIT}_$(echo $EMETER | $JQ -r '.emeter.get_realtime.total')
	SLACK=$($CURL --silent -X POST --data-urlencode "payload={\"channel\": \"${SLACKCHANNEL}\", \"username\": \"SmartBurg\", \"text\": \"${MELDUNG}\", \"icon_emoji\": \"${EMOJI}\"}" $SLACK_HOOK_URL)
else
	rm -f ${MYPATH}/stop_${MAC}_*
	if [ $DEBUG -eq 1 ] ; then echo "# --- Löschen stop Datei für ${MAC}" ; fi
fi

# Beende IP Schleife
done

SLEEP=`sleep 5`

# Set LED off
# sudo bash -c 'echo 0 >/sys/class/leds/led0/brightness'

sleep 0.2

# Set LED on
# sudo bash -c 'echo 1 >/sys/class/leds/led0/brightness'

# Spring zur Endlosschleife
done
