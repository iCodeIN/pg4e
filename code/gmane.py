
# https://www.pg4e.com/code/gmane.py
# https://www.pg4e.com/code/datecompat.py

# https://www.pg4e.com/code/hidden-dist.py
# copy hidden-dist.py to hidden.py
# edit hidden.py and put in your credentials 

# python3 gmane.py
# Pulls data from the web and puts it into messages table

import psycopg2
import time
import ssl
import urllib.request, urllib.parse, urllib.error
from urllib.parse import urljoin
from urllib.parse import urlparse
import re
import hidden
import datecompat

import dateutil.parser as parser # If this import fails - just comment it out

def parsemaildate(md) :
    try:
        pdate = parser.parse(tdate)
        test_at = pdate.isoformat()
        return test_at
    except:
        return datecompat.parsemaildate(md)

# Ignore SSL certificate errors
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

secrets = hidden.secrets()

conn = psycopg2.connect(host=secrets['host'],database=secrets['database'], user=secrets['user'], password=secrets['pass'])
cur = conn.cursor()

baseurl = "http://mbox.dr-chuck.net/sakai.devel/"

cur.execute('''CREATE TABLE IF NOT EXISTS messages
    (id SERIAL, email TEXT, sent_at TIMESTAMPTZ,
     subject TEXT, headers TEXT, body TEXT)''')

# Pick up where we left off
start = None
cur.execute('SELECT max(id) FROM messages' )
try:
    row = cur.fetchone()
    if row is None :
        start = 0
    else:
        start = row[0]
except:
    start = 0

if start is None : start = 0

many = 0
count = 0
fail = 0
while True:
    if ( many < 1 ) :
        conn.commit()
        sval = input('How many messages:')
        if ( len(sval) < 1 ) : break
        many = int(sval)

    start = start + 1
    cur.execute('SELECT id FROM messages WHERE id=%s', (start,) )
    try:
        row = cur.fetchone()
        if row is not None : continue
    except:
        row = None

    many = many - 1
    url = baseurl + str(start) + '/' + str(start + 1)

    text = "None"
    try:
        # Open with a timeout of 30 seconds
        document = urllib.request.urlopen(url, None, 30, context=ctx)
        text = document.read().decode()
        if document.getcode() != 200 :
            print("Error code=",document.getcode(), url)
            break
    except KeyboardInterrupt:
        print('')
        print('Program interrupted by user...')
        break
    except Exception as e:
        print("Unable to retrieve or parse page",url)
        print("Error",e)
        fail = fail + 1
        if fail > 5 : break
        continue

    print(url,len(text))
    count = count + 1

    if not text.startswith("From "):
        print(text)
        print("Did not find From ")
        fail = fail + 1
        if fail > 5 : break
        continue

    pos = text.find("\n\n")
    if pos > 0 :
        hdr = text[:pos]
        body = text[pos+2:]
    else:
        print(text)
        print("Could not find break between headers and body")
        fail = fail + 1
        if fail > 5 : break
        continue

    email = None
    x = re.findall('\nFrom: .* <(\S+@\S+)>\n', hdr)
    if len(x) == 1 :
        email = x[0];
        email = email.strip().lower()
        email = email.replace("<","")
    else:
        x = re.findall('\nFrom: (\S+@\S+)\n', hdr)
        if len(x) == 1 :
            email = x[0];
            email = email.strip().lower()
            email = email.replace("<","")

    sent_at = None
    y = re.findall('\Date: .*, (.*)\n', hdr)
    if len(y) == 1 :
        tdate = y[0]
        tdate = tdate[:26]
        try:
            sent_at = parsemaildate(tdate)
        except:
            print(text)
            print("Parse fail",tdate)
            fail = fail + 1
            if fail > 5 : break
            continue

    subject = None
    z = re.findall('\Subject: (.*)\n', hdr)
    if len(z) == 1 : subject = z[0].strip().lower();

    # Reset the fail counter
    fail = 0
    print("   ",email,sent_at,subject)
    cur.execute('''INSERT INTO Messages (id, email, sent_at, subject, headers, body)
        VALUES ( %s, %s, %s, %s, %s, %s ) ON CONFLICT DO NOTHING''',
               ( start, email, sent_at, subject, hdr, body))
    if count % 50 == 0 : conn.commit()
    if count % 100 == 0 : time.sleep(1)

conn.commit()
cur.close()
