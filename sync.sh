#!/bin/bash

send_files(){
  SERVER=$1
  #echo "send files to $SERVER"
  rsync -rtpqu ~/certs $SERVER:
  rsync -rtpqu ~/challenges $SERVER:
  rsync -rtpqu ~/csr $SERVER:
  rsync -rtpqu ~/sites $SERVER:
  rsync -rtpqu ~/keys $SERVER:
}

#send_files www2
