#!/bin/bash

# Watch and report signal strength every 2 seconds
watch -n 2 'mmcli -m 0 | grep -i signal'
