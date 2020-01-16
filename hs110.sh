#!/bin/bash

if [ "$1" = "debug" ] ; then DEBUG=1 ; else DEBUG=0 ; fi

# Exit if still runs
me=$(basename $0); running=$(ps h -C $me | grep -v $$ | wc -l); [[ $running > 1 ]] && exit;

BC=`which bc`
DATE=`which date`
JQ=`which jq`
WGET=`which wget`
TIMEOUT=`which timeout`

SLACKCHANNEL=<YOUR SLACKCHANNEL>
SLACK_HOOK_URL=https://hooks.slack.com/services/xxxxx/xxxxx/xxxxx

# Brutto Strompreis in ct/kWh mit PUNKT als Trenner
STROMPREIS=30.59
MYPATH=/wo/dein/krempl/liegt
RAMDISK=/ramdisk
TPLINK=$MYPATH/tplink-smartplug.py

if [ ! -d $RAMDISK ] ; then echo "NO RAMDISK - exiting ..." ; exit ; fi

# Dieses Gerät ist
OWNMAC=$(ls -1 ${RAMDISK}/raspi* | cut -d "_" -f2)

if [ ! $OWNMAC ] ; then echo "NO own MAC detectet - exiting ..." ; exit ; fi

# Read ignore list
IGNORE=$($TIMEOUT 2 $MQSUB -v $BROKER -t 'SmartBurg/+/+/ignore' | cut -d"/" -f3)
rm -rf ${RAMDISK}/ignore_*
for TOUCH in $IGNORE ; do 
	touch ${RAMDISK}/ignore_${TOUCH}
	touch ${MYPATH}/ignore_${TOUCH}
	rm -f ${MYPATH}/start_${TOUCH}_*
	rm -f ${MYPATH}/stop_${TOUCH}_*
	if [ $DEBUG -eq 1 ] ; then echo "# --- Ignoreliste: $TOUCH" ; fi
done

# Endlosschleife
# Endlosschleife
# Endlosschleife
while true ; do

# Ausgelesen um
ZEIT=$($DATE +%s)

# Päuschen erst nach dem ersten Durchlauf
# Net wundern, wird erst am Ende des ersten Durchlaufes gesetzt.
$SLEEP

# Abfrage aller gefundenen Dosen
for IP in $(ls -1 ${RAMDISK}/HS110* | cut -d "_" -f3) ; do
MAC=$(ls -1 ${RAMDISK}/HS110*${IP} | cut -d"_" -f2)

# Script-Sprung, wenn die Dose nicht erreichbar ist
$TIMEOUT 1 bash -c "cat < /dev/null > /dev/tcp/${IP}/9999 2> /dev/null" || continue

# Aktuelle Steckdose auslesen
EMETER=$($TPLINK -t $IP -c emeter | grep ^Received | cut -d ":" -f2-)
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
		if [ $DELTA -gt 180 ] ; then 
			INFO=$($TPLINK -t $IP -c info | grep ^Received | cut -d ":" -f2-)
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
			SLACK=$(curl --silent -X POST --data-urlencode "payload={\"channel\": \"${SLACKCHANNEL}\", \"username\": \"SmartBurg\", \"text\": \"${MELDUNG}\", \"icon_emoji\": \"${EMOJI}\"}" $SLACK_HOOK_URL)
			fi

			#### Hier kann noch der SLACK=ok Check rein vor dem löschen
			rm -f ${MYPATH}/start_${MAC}_*
			rm -f ${MYPATH}/stop_${MAC}_*
		fi
	fi
	continue
fi

INFO=$($TPLINK -t $IP -c info | grep ^Received | cut -d ":" -f2-)
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
	SLACK=$(curl --silent -X POST --data-urlencode "payload={\"channel\": \"${SLACKCHANNEL}\", \"username\": \"SmartBurg\", \"text\": \"${MELDUNG}\", \"icon_emoji\": \"${EMOJI}\"}" $SLACK_HOOK_URL)
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
