IDENTIFICATION DIVISION.
PROGRAM-ID. SendPacket-RemovePlayer.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 PACKET-ID        BINARY-LONG             VALUE 59.
    *> buffer used to store the packet data
    01 PAYLOAD          PIC X(1024).
    01 PAYLOADLEN       BINARY-LONG UNSIGNED.
    *> temporary data
    01 INT32            BINARY-LONG.
    01 BUFFER           PIC X(8).
    01 BUFFERLEN        BINARY-LONG UNSIGNED.
LINKAGE SECTION.
    01 LK-HNDL          PIC X(4).
    01 LK-ERRNO         PIC 9(3).
    01 LK-ENTITY-ID     BINARY-LONG.

PROCEDURE DIVISION USING BY REFERENCE LK-HNDL LK-ERRNO LK-ENTITY-ID.
    MOVE 0 TO PAYLOADLEN

    *> number of players
    *> TODO: support sending multiple players
    MOVE 1 TO INT32
    CALL "Encode-VarInt" USING INT32 BUFFER BUFFERLEN
    MOVE BUFFER(1:BUFFERLEN) TO PAYLOAD(PAYLOADLEN + 1:BUFFERLEN)
    ADD BUFFERLEN TO PAYLOADLEN

    *> player UUID
    *> TODO: use a proper UUID
    MOVE X"000000000000" TO PAYLOAD(PAYLOADLEN + 1:12)
    ADD 12 TO PAYLOADLEN
    CALL "Encode-Int" USING LK-ENTITY-ID BUFFER BUFFERLEN
    MOVE BUFFER(1:BUFFERLEN) TO PAYLOAD(PAYLOADLEN + 1:BUFFERLEN)
    ADD BUFFERLEN TO PAYLOADLEN

    *> send packet
    CALL "SendPacket" USING LK-HNDL PACKET-ID PAYLOAD PAYLOADLEN LK-ERRNO
    GOBACK.

END PROGRAM SendPacket-RemovePlayer.
