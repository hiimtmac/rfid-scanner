from rfidlib import RFID
import time
rdr = RFID()

print("Starting...")

while True:
  rdr.wait_for_tag()
#  (error, tag_type) = rdr.request()
#  if not error:
  print("Tag detected")
  (error, uid) = rdr.anticoll()
  if not error:
    print("UID: " + str(uid))
    time.sleep(5)

# Calls GPIO cleanup
rdr.cleanup()
