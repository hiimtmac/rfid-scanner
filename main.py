import RPi.GPIO as GPIO

GPIO.setmode(GPIO.BOARD)
GPIO.setup(18, GPIO.IN, pull_up_down=GPIO.PUD_UP)

#from rfidlib import RFID
#import time
#rdr = RFID()
#
#print("Starting...")
#
#while True:
#  rdr.wait_for_tag()
#  (error, tag_type) = rdr.request()
#  if not error:
#    print("Tag detected, type:", tag_type)
#    time.sleep(2)
#    (error, uid) = rdr.anticoll()
#    if not error:
#      print("UID: " + str(uid))
#      time.sleep(5)
#  else:
#    print("error in request")
#    time.sleep(2)

# Calls GPIO cleanup
#rdr.cleanup()
