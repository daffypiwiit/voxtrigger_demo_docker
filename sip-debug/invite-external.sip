INVITE sip:5255512345678@127.0.0.1 SIP/2.0
Via: SIP/2.0/UDP 192.168.68.116:5062;branch=z9hG4bK-ext001;rport
Max-Forwards: 70
From: <sip:external@192.168.68.116>;tag=ext001
To: <sip:5255512345678@127.0.0.1>
Call-ID: test-invite-001@192.168.68.116
CSeq: 1 INVITE
Contact: <sip:external@192.168.68.116:5062>
User-Agent: external-test
Content-Type: application/sdp
Content-Length: 129

v=0
o=- 0 0 IN IP4 192.168.68.116
s=-
c=IN IP4 192.168.68.116
t=0 0
m=audio 4000 RTP/AVP 0 8 101
a=rtpmap:0 PCMU/8000
a=rtpmap:8 PCMA/8000
a=rtpmap:101 telephone-event/8000
