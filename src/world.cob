*> --- World-FindChunkIndex ---
*> Find a chunk that is present and has the given coordinates.
IDENTIFICATION DIVISION.
PROGRAM-ID. World-FindChunkIndex.

DATA DIVISION.
WORKING-STORAGE SECTION.
    *> World data
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-CHUNK-X           BINARY-LONG.
    01 LK-CHUNK-Z           BINARY-LONG.
    01 LK-CHUNK-INDEX       BINARY-LONG UNSIGNED.

PROCEDURE DIVISION USING LK-CHUNK-X LK-CHUNK-Z LK-CHUNK-INDEX.
    PERFORM VARYING LK-CHUNK-INDEX FROM 1 BY 1 UNTIL LK-CHUNK-INDEX > WORLD-CHUNK-COUNT
        IF WORLD-CHUNK-PRESENT(LK-CHUNK-INDEX) > 0 AND LK-CHUNK-X = WORLD-CHUNK-X(LK-CHUNK-INDEX) AND LK-CHUNK-Z = WORLD-CHUNK-Z(LK-CHUNK-INDEX)
            EXIT PERFORM
        END-IF
    END-PERFORM
    IF LK-CHUNK-INDEX > WORLD-CHUNK-COUNT
        MOVE 0 TO LK-CHUNK-INDEX
    END-IF
    GOBACK.

END PROGRAM World-FindChunkIndex.

*> --- World-AllocateChunk ---
*> Find a free chunk slot. If a chunk with the given coordinates is present, it is freed first.
*> All blocks in the chunk are set to air, and the coordinates are set. The chunk is, however, not marked as present.
IDENTIFICATION DIVISION.
PROGRAM-ID. World-AllocateChunk.

DATA DIVISION.
WORKING-STORAGE SECTION.
    *> Constants
    01 C-MINECRAFT-WORLDGEN-BIOME       PIC X(50)           VALUE "minecraft:worldgen/biome".
    01 C-MINECRAFT-PLAINS               PIC X(50)           VALUE "minecraft:plains".
    *> Temporary variables
    01 BIOME-ID             BINARY-LONG UNSIGNED.
    01 SECTION-INDEX        BINARY-LONG UNSIGNED.
    *> World data
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-CHUNK-X           BINARY-LONG.
    01 LK-CHUNK-Z           BINARY-LONG.
    01 LK-CHUNK-INDEX       BINARY-LONG UNSIGNED.

PROCEDURE DIVISION USING LK-CHUNK-X LK-CHUNK-Z LK-CHUNK-INDEX.
    PERFORM VARYING LK-CHUNK-INDEX FROM 1 BY 1 UNTIL LK-CHUNK-INDEX > WORLD-CHUNK-COUNT
        IF WORLD-CHUNK-PRESENT(LK-CHUNK-INDEX) = 0 OR (LK-CHUNK-X = WORLD-CHUNK-X(LK-CHUNK-INDEX) AND LK-CHUNK-Z = WORLD-CHUNK-Z(LK-CHUNK-INDEX))
            EXIT PERFORM
        END-IF
    END-PERFORM
    IF LK-CHUNK-INDEX > WORLD-CHUNK-COUNT
        MOVE 0 TO LK-CHUNK-INDEX
        GOBACK
    END-IF
    INITIALIZE WORLD-CHUNK(LK-CHUNK-INDEX)
    MOVE LK-CHUNK-X TO WORLD-CHUNK-X(LK-CHUNK-INDEX)
    MOVE LK-CHUNK-Z TO WORLD-CHUNK-Z(LK-CHUNK-INDEX)
    INITIALIZE WORLD-BLOCK-ENTITIES(LK-CHUNK-INDEX) REPLACING NUMERIC BY -1

    *> Set all sections to the plains biome
    *> TODO: This is a hack. We should have a proper biome system.
    CALL "Registries-Get-EntryId" USING C-MINECRAFT-WORLDGEN-BIOME C-MINECRAFT-PLAINS BIOME-ID
    PERFORM VARYING SECTION-INDEX FROM 1 BY 1 UNTIL SECTION-INDEX > WORLD-SECTION-COUNT
        MOVE BIOME-ID TO WORLD-SECTION-BIOME-ID(LK-CHUNK-INDEX, SECTION-INDEX)
    END-PERFORM

    GOBACK.

END PROGRAM World-AllocateChunk.

*> --- World-GenerateChunk ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-GenerateChunk.

DATA DIVISION.
WORKING-STORAGE SECTION.
    *> Constants
    01 C-MINECRAFT-STONE            PIC X(50) VALUE "minecraft:stone".
    01 C-MINECRAFT-GRASS_BLOCK      PIC X(50) VALUE "minecraft:grass_block".
    *> World data
    COPY DD-WORLD.
LOCAL-STORAGE SECTION.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    01 SECTION-INDEX        BINARY-LONG UNSIGNED.
    01 BLOCK-INDEX          BINARY-LONG UNSIGNED.
    01 TEMP-INT32           BINARY-LONG.
LINKAGE SECTION.
    01 LK-CHUNK-X           BINARY-LONG.
    01 LK-CHUNK-Z           BINARY-LONG.

PROCEDURE DIVISION USING LK-CHUNK-X LK-CHUNK-Z.
    CALL "World-AllocateChunk" USING LK-CHUNK-X LK-CHUNK-Z CHUNK-INDEX
    IF CHUNK-INDEX = 0
        *> TODO handle this case
        GOBACK
    END-IF

    *> turn all blocks with Y <= 63 (= the bottom 128 blocks = the bottom 8 sections) into stone
    CALL "Blocks-Get-DefaultStateId" USING C-MINECRAFT-STONE TEMP-INT32
    PERFORM VARYING SECTION-INDEX FROM 1 BY 1 UNTIL SECTION-INDEX > 8
        PERFORM VARYING BLOCK-INDEX FROM 1 BY 1 UNTIL BLOCK-INDEX > 4096
            MOVE TEMP-INT32 TO WORLD-BLOCK-ID(CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX)
        END-PERFORM
        MOVE 4096 TO WORLD-SECTION-NON-AIR(CHUNK-INDEX, SECTION-INDEX)
    END-PERFORM

    *> turn all blocks with Y = 63 (i.e., the top 16x16 blocks) into grass
    CALL "Blocks-Get-DefaultStateId" USING C-MINECRAFT-GRASS_BLOCK TEMP-INT32
    MOVE 8 TO SECTION-INDEX
    COMPUTE BLOCK-INDEX = 4096 - 256 + 1
    PERFORM 256 TIMES
        MOVE TEMP-INT32 TO WORLD-BLOCK-ID(CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX)
        *> Note: No need to increment WORLD-SECTION-NON-AIR, as the section is already full
        ADD 1 TO BLOCK-INDEX
    END-PERFORM

    *> mark the chunk as present and dirty (i.e., needing to be saved)
    MOVE 1 TO WORLD-CHUNK-PRESENT(CHUNK-INDEX)
    MOVE 1 TO WORLD-CHUNK-DIRTY(CHUNK-INDEX)

    GOBACK.

END PROGRAM World-GenerateChunk.

*> --- World-SaveChunk ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-SaveChunk.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 C-MINECRAFT-BLOCK_ENTITY_TYPE PIC X(32) VALUE "minecraft:block_entity_type".
    01 NBT-BUFFER               PIC X(1048576).
    01 NBT-BUFFER-LENGTH        BINARY-LONG UNSIGNED.
    01 CHUNK-SECTION-MIN-Y      BINARY-LONG             VALUE -4.
    *> Temporary variables
    01 TAG-NAME                 PIC X(256).
    01 NAME-LEN                 BINARY-LONG UNSIGNED.
    01 STR                      PIC X(256).
    01 STR-LEN                  BINARY-LONG UNSIGNED.
    01 INT8                     BINARY-CHAR.
    01 INT32                    BINARY-LONG.
    01 SECTION-INDEX            BINARY-LONG UNSIGNED.
    01 BLOCK-INDEX              BINARY-LONG UNSIGNED.
    01 CURRENT-BLOCK-ID         BINARY-LONG UNSIGNED.
    01 PALETTE-LENGTH           BINARY-LONG UNSIGNED.
    01 PALETTE-BITS             BINARY-LONG UNSIGNED.
    01 PALETTE-BITS-POW         BINARY-LONG UNSIGNED.
    01 BLOCKS-PER-LONG          BINARY-LONG UNSIGNED.
    01 LONG-ARRAY-LENGTH        BINARY-LONG UNSIGNED.
    01 LONG-ARRAY-ENTRY         BINARY-LONG-LONG UNSIGNED.
    01 LONG-ARRAY-ENTRY-SIGNED  REDEFINES LONG-ARRAY-ENTRY BINARY-LONG-LONG.
    01 LONG-ARRAY-MULTIPLIER    BINARY-LONG-LONG UNSIGNED.
    COPY DD-BLOCK-STATE REPLACING LEADING ==PREFIX== BY ==PALETTE-BLOCK==.
    01 PROPERTY-INDEX           BINARY-LONG UNSIGNED.
    01 ENTITY-COUNT             BINARY-LONG UNSIGNED.
    01 ENTITY-X                 BINARY-LONG.
    01 ENTITY-Y                 BINARY-LONG.
    01 ENTITY-Z                 BINARY-LONG.
    *> World data
    COPY DD-WORLD.
    *> A map of block state indices to palette indices
    78 BLOCK-PALETTE-CAPACITY VALUE 100000.
    01 BLOCK-PALETTE-INDICES.
        02 BLOCK-PALETTE-INDEX OCCURS BLOCK-PALETTE-CAPACITY TIMES BINARY-SHORT UNSIGNED.
LOCAL-STORAGE SECTION.
    COPY DD-NBT-ENCODER.
LINKAGE SECTION.
    01 LK-CHUNK-INDEX           BINARY-LONG UNSIGNED.
    01 LK-FAILURE               BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-CHUNK-INDEX LK-FAILURE.
    MOVE 0 TO LK-FAILURE

    *> start root tag
    MOVE 1 TO NBT-ENCODER-OFFSET
    CALL "NbtEncode-RootCompound" USING NBT-ENCODER-STATE NBT-BUFFER

    *> chunk position
    MOVE 4 TO NAME-LEN
    MOVE "xPos" TO TAG-NAME
    CALL "NbtEncode-Int" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN WORLD-CHUNK-X(LK-CHUNK-INDEX)
    MOVE "zPos" TO TAG-NAME
    CALL "NbtEncode-Int" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN WORLD-CHUNK-Z(LK-CHUNK-INDEX)
    MOVE "yPos" TO TAG-NAME
    CALL "NbtEncode-Int" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN CHUNK-SECTION-MIN-Y

    *> start chunk sections
    MOVE "sections" TO TAG-NAME
    MOVE 8 TO NAME-LEN
    CALL "NbtEncode-List" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN

    PERFORM VARYING SECTION-INDEX FROM 1 BY 1 UNTIL SECTION-INDEX > WORLD-SECTION-COUNT
        *> only write sections that are not entirely air
        *> Note: The official format stores all sections, but it seems unnecessary, so we don't.
        IF WORLD-SECTION-NON-AIR(LK-CHUNK-INDEX, SECTION-INDEX) > 0
            *> start section
            CALL "NbtEncode-Compound" USING NBT-ENCODER-STATE NBT-BUFFER OMITTED OMITTED

            *> section position
            MOVE "Y" TO TAG-NAME
            MOVE 1 TO NAME-LEN
            COMPUTE INT8 = SECTION-INDEX - 1 + CHUNK-SECTION-MIN-Y
            CALL "NbtEncode-Byte" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN INT8

            *> block states - palette and data
            MOVE "block_states" TO TAG-NAME
            MOVE 12 TO NAME-LEN
            CALL "NbtEncode-Compound" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN

            *> palette
            MOVE "palette" TO TAG-NAME
            MOVE 7 TO NAME-LEN
            CALL "NbtEncode-List" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN

            MOVE 0 TO PALETTE-LENGTH
            INITIALIZE BLOCK-PALETTE-INDICES

            PERFORM VARYING BLOCK-INDEX FROM 1 BY 1 UNTIL BLOCK-INDEX > 4096
                *> If the block is not in the palette, add it
                MOVE WORLD-BLOCK-ID(LK-CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX) TO CURRENT-BLOCK-ID
                IF BLOCK-PALETTE-INDEX(CURRENT-BLOCK-ID + 1) = 0
                    ADD 1 TO PALETTE-LENGTH
                    MOVE PALETTE-LENGTH TO BLOCK-PALETTE-INDEX(CURRENT-BLOCK-ID + 1)
                    CALL "Blocks-Get-StateDescription" USING CURRENT-BLOCK-ID PALETTE-BLOCK-DESCRIPTION

                    *> start palette entry
                    CALL "NbtEncode-Compound" USING NBT-ENCODER-STATE NBT-BUFFER OMITTED OMITTED

                    *> name
                    MOVE "Name" TO TAG-NAME
                    MOVE 4 TO NAME-LEN
                    MOVE FUNCTION STORED-CHAR-LENGTH(PALETTE-BLOCK-NAME) TO STR-LEN
                    CALL "NbtEncode-String" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN PALETTE-BLOCK-NAME STR-LEN

                    IF PALETTE-BLOCK-PROPERTY-COUNT > 0
                        *> start properties
                        MOVE "Properties" TO TAG-NAME
                        MOVE 10 TO NAME-LEN
                        CALL "NbtEncode-Compound" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN

                        PERFORM VARYING PROPERTY-INDEX FROM 1 BY 1 UNTIL PROPERTY-INDEX > PALETTE-BLOCK-PROPERTY-COUNT
                            MOVE PALETTE-BLOCK-PROPERTY-NAME(PROPERTY-INDEX) TO TAG-NAME
                            MOVE FUNCTION STORED-CHAR-LENGTH(TAG-NAME) TO NAME-LEN
                            MOVE PALETTE-BLOCK-PROPERTY-VALUE(PROPERTY-INDEX) TO STR
                            MOVE FUNCTION STORED-CHAR-LENGTH(STR) TO STR-LEN
                            CALL "NbtEncode-String" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN STR STR-LEN
                        END-PERFORM

                        *> end properties
                        CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER
                    END-IF

                    *> end palette entry
                    CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER
                END-IF
            END-PERFORM

            *> end palette
            CALL "NbtEncode-EndList" USING NBT-ENCODER-STATE NBT-BUFFER

            *> Note: We only need to encode data if the palette length is greater than 1
            IF PALETTE-LENGTH > 1
                *> number of bits needed = ceil(log2(palette length - 1)) = bits needed to store (palette length - 1)
                COMPUTE INT32 = PALETTE-LENGTH - 1
                CALL "LeadingZeros32" USING INT32 PALETTE-BITS
                *> However, Minecraft uses a minimum of 4 bits
                COMPUTE PALETTE-BITS = FUNCTION MAX(32 - PALETTE-BITS, 4)
                COMPUTE PALETTE-BITS-POW = 2 ** PALETTE-BITS

                *> length of packed long array
                DIVIDE 64 BY PALETTE-BITS GIVING BLOCKS-PER-LONG
                DIVIDE 4096 BY BLOCKS-PER-LONG GIVING LONG-ARRAY-LENGTH ROUNDED MODE IS TOWARD-GREATER

                *> data (packed long array)
                MOVE "data" TO TAG-NAME
                MOVE 4 TO NAME-LEN
                CALL "NbtEncode-LongArray" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN LONG-ARRAY-LENGTH

                MOVE 1 TO BLOCK-INDEX
                PERFORM LONG-ARRAY-LENGTH TIMES
                    MOVE 0 TO LONG-ARRAY-ENTRY
                    MOVE 1 TO LONG-ARRAY-MULTIPLIER
                    PERFORM FUNCTION MIN(BLOCKS-PER-LONG, 4096 - BLOCK-INDEX + 1) TIMES
                        MOVE WORLD-BLOCK-ID(LK-CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX) TO CURRENT-BLOCK-ID
                        COMPUTE LONG-ARRAY-ENTRY = LONG-ARRAY-ENTRY + LONG-ARRAY-MULTIPLIER * (BLOCK-PALETTE-INDEX(CURRENT-BLOCK-ID + 1) - 1)
                        MULTIPLY LONG-ARRAY-MULTIPLIER BY PALETTE-BITS-POW GIVING LONG-ARRAY-MULTIPLIER
                        ADD 1 TO BLOCK-INDEX
                    END-PERFORM
                    CALL "NbtEncode-Long" USING NBT-ENCODER-STATE NBT-BUFFER OMITTED OMITTED LONG-ARRAY-ENTRY-SIGNED
                END-PERFORM
            END-IF

            *> end block states
            CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER

            *> end section
            CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER
        END-IF
    END-PERFORM

    *> end chunk sections
    CALL "NbtEncode-EndList" USING NBT-ENCODER-STATE NBT-BUFFER

    *> start block entities
    MOVE "block_entities" TO TAG-NAME
    MOVE 14 TO NAME-LEN
    CALL "NbtEncode-List" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN

    IF WORLD-BLOCK-ENTITY-COUNT(LK-CHUNK-INDEX) > 0
        MOVE 1 TO BLOCK-INDEX
        MOVE 0 TO ENTITY-COUNT
        PERFORM 98304 TIMES
            IF WORLD-BLOCK-ENTITY-ID(LK-CHUNK-INDEX, BLOCK-INDEX) >= 0
                *> start block entity
                CALL "NbtEncode-Compound" USING NBT-ENCODER-STATE NBT-BUFFER

                *> id (registry: "minecraft:block_entity_type")
                MOVE "id" TO TAG-NAME
                MOVE 2 TO NAME-LEN
                MOVE WORLD-BLOCK-ENTITY-ID(LK-CHUNK-INDEX, BLOCK-INDEX) TO INT32
                CALL "Registries-Get-EntryName" USING C-MINECRAFT-BLOCK_ENTITY_TYPE INT32 STR
                MOVE FUNCTION STORED-CHAR-LENGTH(STR) TO STR-LEN
                CALL "NbtEncode-String" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN STR STR-LEN

                *> x, y, z
                SUBTRACT 1 FROM BLOCK-INDEX GIVING INT32
                DIVIDE INT32 BY 16 GIVING INT32 REMAINDER ENTITY-X
                DIVIDE INT32 BY 16 GIVING INT32 REMAINDER ENTITY-Z
                SUBTRACT 64 FROM INT32 GIVING ENTITY-Y
                *> x and z are in the world coordinate system
                COMPUTE ENTITY-X = ENTITY-X + WORLD-CHUNK-X(LK-CHUNK-INDEX) * 16
                COMPUTE ENTITY-Z = ENTITY-Z + WORLD-CHUNK-Z(LK-CHUNK-INDEX) * 16
                *> store the coordinates
                MOVE 1 TO NAME-LEN
                MOVE "x" TO TAG-NAME
                CALL "NbtEncode-Int" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN ENTITY-X
                MOVE "y" TO TAG-NAME
                CALL "NbtEncode-Int" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN ENTITY-Y
                MOVE "z" TO TAG-NAME
                CALL "NbtEncode-Int" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN ENTITY-Z

                *> TODO: write the block entity-specific data

                *> end block entity
                CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER

                *> stop the loop once all block entities have been written
                ADD 1 TO ENTITY-COUNT
                IF ENTITY-COUNT >= WORLD-BLOCK-ENTITY-COUNT(LK-CHUNK-INDEX)
                    EXIT PERFORM
                END-IF
            END-IF
            ADD 1 TO BLOCK-INDEX
        END-PERFORM
    END-IF

    *> end block entities
    CALL "NbtEncode-EndList" USING NBT-ENCODER-STATE NBT-BUFFER

    *> end root tag
    CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER

    *> Save the chunk
    COMPUTE NBT-BUFFER-LENGTH = NBT-ENCODER-OFFSET - 1
    CALL "Region-WriteChunkData" USING WORLD-CHUNK-X(LK-CHUNK-INDEX) WORLD-CHUNK-Z(LK-CHUNK-INDEX) NBT-BUFFER NBT-BUFFER-LENGTH LK-FAILURE
    IF LK-FAILURE NOT = 0
        GOBACK
    END-IF

    MOVE 0 TO WORLD-CHUNK-DIRTY(LK-CHUNK-INDEX)

    GOBACK.

END PROGRAM World-SaveChunk.

*> --- World-LoadChunk ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-LoadChunk.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 C-MINECRAFT-BLOCK_ENTITY_TYPE PIC X(32) VALUE "minecraft:block_entity_type".
    01 NBT-BUFFER               PIC X(1048576).
    01 NBT-BUFFER-LENGTH        BINARY-LONG UNSIGNED.
    *> Temporary variables
    01 SEEK-FOUND               BINARY-LONG UNSIGNED.
    COPY DD-NBT-DECODER REPLACING LEADING ==NBT-DECODER== BY ==NBT-SEEK==.
    COPY DD-NBT-DECODER REPLACING LEADING ==NBT-DECODER== BY ==NBT-BLOCK-STATES==.
    01 EXPECTED-TAG             PIC X(256).
    01 AT-END                   BINARY-CHAR UNSIGNED.
    01 TAG-NAME                 PIC X(256).
    01 NAME-LEN                 BINARY-LONG UNSIGNED.
    01 STR                      PIC X(256).
    01 STR-LEN                  BINARY-LONG UNSIGNED.
    01 INT8                     BINARY-CHAR.
    01 INT32                    BINARY-LONG.
    01 CHUNK-X                  BINARY-LONG.
    01 CHUNK-Z                  BINARY-LONG.
    01 CHUNK-SECTION-MIN-Y      BINARY-LONG.
    01 CHUNK-INDEX              BINARY-LONG UNSIGNED.
    01 LOADED-SECTION-COUNT     BINARY-LONG UNSIGNED.
    01 SECTION-INDEX            BINARY-LONG UNSIGNED.
    01 BLOCK-INDEX              BINARY-LONG UNSIGNED.
    01 CURRENT-BLOCK-ID         BINARY-LONG UNSIGNED.
    01 PALETTE-LENGTH           BINARY-LONG UNSIGNED.
    01 PALETTE-INDEX            BINARY-SHORT UNSIGNED.
    01 PALETTE-BITS             BINARY-LONG UNSIGNED.
    01 PALETTE-BITS-POW         BINARY-LONG UNSIGNED.
    01 BLOCKS-PER-LONG          BINARY-LONG UNSIGNED.
    01 LONG-ARRAY-LENGTH        BINARY-LONG UNSIGNED.
    01 LONG-ARRAY-ENTRY         BINARY-LONG-LONG UNSIGNED.
    01 LONG-ARRAY-ENTRY-SIGNED  REDEFINES LONG-ARRAY-ENTRY BINARY-LONG-LONG.
    COPY DD-BLOCK-STATE REPLACING LEADING ==PREFIX== BY ==PALETTE-BLOCK==.
    *> A map of palette indices to block state IDs
    01 BLOCK-STATE-IDS          BINARY-LONG UNSIGNED OCCURS 4096 TIMES.
    *> block entity data
    01 ENTITY-COUNT             BINARY-LONG UNSIGNED.
    01 ENTITY-ID                BINARY-LONG.
    01 ENTITY-X                 BINARY-LONG.
    01 ENTITY-Y                 BINARY-LONG.
    01 ENTITY-Z                 BINARY-LONG.
    *> World data
    COPY DD-WORLD.
LOCAL-STORAGE SECTION.
    COPY DD-NBT-DECODER.
LINKAGE SECTION.
    01 LK-CHUNK-X               BINARY-LONG.
    01 LK-CHUNK-Z               BINARY-LONG.
    01 LK-FAILURE               BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-CHUNK-X LK-CHUNK-Z LK-FAILURE.
    CALL "Region-ReadChunkData" USING LK-CHUNK-X LK-CHUNK-Z NBT-BUFFER NBT-BUFFER-LENGTH LK-FAILURE
    IF LK-FAILURE NOT = 0 OR NBT-BUFFER-LENGTH = 0
        MOVE 1 TO LK-FAILURE
        GOBACK
    END-IF

    *> start root tag
    MOVE 1 TO NBT-DECODER-OFFSET
    CALL "NbtDecode-RootCompound" USING NBT-DECODER-STATE NBT-BUFFER

    *> Do a first pass to get the chunk X, Z, and Y values.
    *> The way we write NBT, they should come before any larger pieces of data, but this is not strictly guaranteed.
    MOVE NBT-DECODER-STATE TO NBT-SEEK-STATE
    MOVE 0 TO SEEK-FOUND
    PERFORM UNTIL EXIT
        CALL "NbtDecode-Peek" USING NBT-SEEK-STATE NBT-BUFFER AT-END TAG-NAME NAME-LEN
        IF AT-END > 0
            EXIT PERFORM
        END-IF
        EVALUATE TAG-NAME(1:NAME-LEN)
            WHEN "xPos"
                CALL "NbtDecode-Int" USING NBT-SEEK-STATE NBT-BUFFER CHUNK-X
                ADD 1 TO SEEK-FOUND
            WHEN "zPos"
                CALL "NbtDecode-Int" USING NBT-SEEK-STATE NBT-BUFFER CHUNK-Z
                ADD 1 TO SEEK-FOUND
            WHEN "yPos"
                CALL "NbtDecode-Int" USING NBT-SEEK-STATE NBT-BUFFER CHUNK-SECTION-MIN-Y
                ADD 1 TO SEEK-FOUND
            WHEN OTHER
                CALL "NbtDecode-Skip" USING NBT-SEEK-STATE NBT-BUFFER
        END-EVALUATE
        IF SEEK-FOUND = 3
            EXIT PERFORM
        END-IF
    END-PERFORM

    *> Allocate a chunk slot
    CALL "World-AllocateChunk" USING CHUNK-X CHUNK-Z CHUNK-INDEX
    IF CHUNK-INDEX = 0
        MOVE 1 TO LK-FAILURE
        GOBACK
    END-IF

    *> Skip ahead until we find the sections tag.
    MOVE "sections" TO EXPECTED-TAG
    CALL "SkipUntilTag" USING NBT-DECODER-STATE NBT-BUFFER EXPECTED-TAG AT-END
    IF AT-END > 0
        MOVE 1 TO LK-FAILURE
        GOBACK
    END-IF

    *> start sections
    CALL "NbtDecode-List" USING NBT-DECODER-STATE NBT-BUFFER LOADED-SECTION-COUNT

    PERFORM LOADED-SECTION-COUNT TIMES
        *> start section
        CALL "NbtDecode-Compound" USING NBT-DECODER-STATE NBT-BUFFER

        *> Do a first pass to get the Y value
        MOVE NBT-DECODER-STATE TO NBT-SEEK-STATE
        MOVE "Y" TO EXPECTED-TAG
        CALL "SkipUntilTag" USING NBT-SEEK-STATE NBT-BUFFER EXPECTED-TAG AT-END
        IF AT-END > 0
            MOVE 1 TO LK-FAILURE
            GOBACK
        END-IF
        CALL "NbtDecode-Byte" USING NBT-SEEK-STATE NBT-BUFFER INT8
        COMPUTE SECTION-INDEX = INT8 + 1 - CHUNK-SECTION-MIN-Y

        *> Decode the block states
        MOVE "block_states" TO EXPECTED-TAG
        CALL "SkipUntilTag" USING NBT-DECODER-STATE NBT-BUFFER EXPECTED-TAG AT-END
        IF AT-END > 0
            MOVE 1 TO LK-FAILURE
            GOBACK
        END-IF

        *> start block states
        CALL "NbtDecode-Compound" USING NBT-DECODER-STATE NBT-BUFFER
        MOVE NBT-DECODER-STATE TO NBT-BLOCK-STATES-STATE

        *> Skip to the palette
        MOVE "palette" TO EXPECTED-TAG
        CALL "SkipUntilTag" USING NBT-DECODER-STATE NBT-BUFFER EXPECTED-TAG AT-END
        IF AT-END > 0
            MOVE 1 TO LK-FAILURE
            GOBACK
        END-IF

        *> start palette
        CALL "NbtDecode-List" USING NBT-DECODER-STATE NBT-BUFFER PALETTE-LENGTH

        PERFORM VARYING PALETTE-INDEX FROM 1 BY 1 UNTIL PALETTE-INDEX > PALETTE-LENGTH
            *> start palette entry
            CALL "NbtDecode-Compound" USING NBT-DECODER-STATE NBT-BUFFER
            MOVE 0 TO PALETTE-BLOCK-PROPERTY-COUNT

            PERFORM UNTIL EXIT
                CALL "NbtDecode-Peek" USING NBT-DECODER-STATE NBT-BUFFER AT-END TAG-NAME NAME-LEN
                IF AT-END > 0
                    EXIT PERFORM
                END-IF
                EVALUATE TAG-NAME(1:NAME-LEN)
                    WHEN "Name"
                        CALL "NbtDecode-String" USING NBT-DECODER-STATE NBT-BUFFER STR STR-LEN
                        MOVE STR(1:STR-LEN) TO PALETTE-BLOCK-NAME

                    WHEN "Properties"
                        CALL "NbtDecode-Compound" USING NBT-DECODER-STATE NBT-BUFFER
                        PERFORM UNTIL EXIT
                            CALL "NbtDecode-Peek" USING NBT-DECODER-STATE NBT-BUFFER AT-END TAG-NAME NAME-LEN
                            IF AT-END > 0
                                EXIT PERFORM
                            END-IF
                            ADD 1 TO PALETTE-BLOCK-PROPERTY-COUNT
                            CALL "NbtDecode-String" USING NBT-DECODER-STATE NBT-BUFFER STR STR-LEN
                            MOVE TAG-NAME(1:NAME-LEN) TO PALETTE-BLOCK-PROPERTY-NAME(PALETTE-BLOCK-PROPERTY-COUNT)
                            MOVE STR(1:STR-LEN) TO PALETTE-BLOCK-PROPERTY-VALUE(PALETTE-BLOCK-PROPERTY-COUNT)
                        END-PERFORM
                        CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER

                    WHEN OTHER
                        CALL "NbtDecode-Skip" USING NBT-DECODER-STATE NBT-BUFFER
                END-EVALUATE
            END-PERFORM

            *> end palette entry
            CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER
            CALL "Blocks-Get-StateId" USING PALETTE-BLOCK-DESCRIPTION BLOCK-STATE-IDS(PALETTE-INDEX)
        END-PERFORM

        *> end palette
        CALL "NbtDecode-EndList" USING NBT-DECODER-STATE NBT-BUFFER

        *> If the palette has length 1, we don't care about the data. In fact, it might not be there.
        IF PALETTE-LENGTH = 1
            *> Fill the section with the singular block state (unless it is air).
            MOVE BLOCK-STATE-IDS(1) TO CURRENT-BLOCK-ID
            IF CURRENT-BLOCK-ID > 0
                INITIALIZE WORLD-SECTION-BLOCKS(CHUNK-INDEX, SECTION-INDEX) REPLACING NUMERIC BY CURRENT-BLOCK-ID
                MOVE 4096 TO WORLD-SECTION-NON-AIR(CHUNK-INDEX, SECTION-INDEX)
            END-IF
        ELSE
            *> Reset the state to the beginning of the block states compound, since "data" may come before "palette".
            *> We don't write NBT this way, but Minecraft does.
            MOVE NBT-BLOCK-STATES-STATE TO NBT-DECODER-STATE

            *> Skip to the data
            MOVE "data" TO EXPECTED-TAG
            CALL "SkipUntilTag" USING NBT-DECODER-STATE NBT-BUFFER EXPECTED-TAG AT-END
            IF AT-END > 0
                MOVE 1 TO LK-FAILURE
                GOBACK
            END-IF

            *> read packed long array
            CALL "NbtDecode-List" USING NBT-DECODER-STATE NBT-BUFFER LONG-ARRAY-LENGTH

            *> number of bits per block = ceil(log2(palette length - 1)) = bits needed to store (palette length - 1)
            COMPUTE INT32 = PALETTE-LENGTH - 1
            CALL "LeadingZeros32" USING INT32 PALETTE-BITS
            *> However, Minecraft uses a minimum of 4 bits
            COMPUTE PALETTE-BITS = FUNCTION MAX(32 - PALETTE-BITS, 4)
            DIVIDE 64 BY PALETTE-BITS GIVING BLOCKS-PER-LONG
            COMPUTE PALETTE-BITS-POW = 2 ** PALETTE-BITS

            MOVE 1 TO BLOCK-INDEX
            PERFORM LONG-ARRAY-LENGTH TIMES
                CALL "NbtDecode-Long" USING NBT-DECODER-STATE NBT-BUFFER LONG-ARRAY-ENTRY-SIGNED
                PERFORM FUNCTION MIN(BLOCKS-PER-LONG, 4096 - BLOCK-INDEX + 1) TIMES
                    DIVIDE LONG-ARRAY-ENTRY BY PALETTE-BITS-POW GIVING LONG-ARRAY-ENTRY REMAINDER PALETTE-INDEX
                    MOVE BLOCK-STATE-IDS(PALETTE-INDEX + 1) TO CURRENT-BLOCK-ID
                    IF CURRENT-BLOCK-ID > 0
                        MOVE CURRENT-BLOCK-ID TO WORLD-BLOCK-ID(CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX)
                        ADD 1 TO WORLD-SECTION-NON-AIR(CHUNK-INDEX, SECTION-INDEX)
                    END-IF
                    ADD 1 TO BLOCK-INDEX
                END-PERFORM
            END-PERFORM

            *> end data
            CALL "NbtDecode-EndList" USING NBT-DECODER-STATE NBT-BUFFER
        END-IF

        *> end block states
        CALL "SkipRemainingTags" USING NBT-DECODER-STATE NBT-BUFFER
        CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER

        *> end section
        CALL "SkipRemainingTags" USING NBT-DECODER-STATE NBT-BUFFER
        CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER
    END-PERFORM

    *> end sections
    CALL "NbtDecode-EndList" USING NBT-DECODER-STATE NBT-BUFFER

    *> Skip to the block entities
    *> TODO: make this position-independent
    MOVE "block_entities" TO EXPECTED-TAG
    CALL "SkipUntilTag" USING NBT-DECODER-STATE NBT-BUFFER EXPECTED-TAG AT-END
    IF AT-END = 0
        CALL "NbtDecode-List" USING NBT-DECODER-STATE NBT-BUFFER ENTITY-COUNT
        MOVE ENTITY-COUNT TO WORLD-BLOCK-ENTITY-COUNT(CHUNK-INDEX)
        PERFORM ENTITY-COUNT TIMES
            CALL "NbtDecode-Compound" USING NBT-DECODER-STATE NBT-BUFFER
            PERFORM UNTIL EXIT
                CALL "NbtDecode-Peek" USING NBT-DECODER-STATE NBT-BUFFER AT-END TAG-NAME NAME-LEN
                IF AT-END > 0
                    EXIT PERFORM
                END-IF
                EVALUATE TAG-NAME(1:NAME-LEN)
                    WHEN "id"
                        CALL "NbtDecode-String" USING NBT-DECODER-STATE NBT-BUFFER STR STR-LEN
                        CALL "Registries-Get-EntryId" USING C-MINECRAFT-BLOCK_ENTITY_TYPE STR(1:STR-LEN) ENTITY-ID
                    WHEN "x"
                        CALL "NbtDecode-Int" USING NBT-DECODER-STATE NBT-BUFFER ENTITY-X
                    WHEN "y"
                        CALL "NbtDecode-Int" USING NBT-DECODER-STATE NBT-BUFFER ENTITY-Y
                    WHEN "z"
                        CALL "NbtDecode-Int" USING NBT-DECODER-STATE NBT-BUFFER ENTITY-Z
                    WHEN OTHER
                        CALL "NbtDecode-Skip" USING NBT-DECODER-STATE NBT-BUFFER
                END-EVALUATE
            END-PERFORM
            *> convert to chunk-relative coordinates
            COMPUTE INT32 = FUNCTION MOD(ENTITY-X, 16) + 16 * (FUNCTION MOD(ENTITY-Z, 16) + 16 * (ENTITY-Y + 64)) + 1
            MOVE ENTITY-ID TO WORLD-BLOCK-ENTITY-ID(CHUNK-INDEX, INT32)
            CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER
        END-PERFORM
        CALL "NbtDecode-EndList" USING NBT-DECODER-STATE NBT-BUFFER
    END-IF

    *> end root tag
    CALL "SkipRemainingTags" USING NBT-DECODER-STATE NBT-BUFFER
    CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER

    *> mark the chunk as present and clean (i.e., not needing to be saved)
    MOVE 1 TO WORLD-CHUNK-PRESENT(CHUNK-INDEX)
    MOVE 0 TO WORLD-CHUNK-DIRTY(CHUNK-INDEX)

    GOBACK.

    *> --- SkipUntilTag ---
    *> A utility procedure to skip until a tag with a given name is found. If found, the offset will be set to the
    *> start of the tag. Otherwise, the offset will be at the end of the compound, and the "at end" flag will be set.
    IDENTIFICATION DIVISION.
    PROGRAM-ID. SkipUntilTag.

    DATA DIVISION.
    WORKING-STORAGE SECTION.
        01 TAG-NAME             PIC X(256).
        01 NAME-LEN             BINARY-LONG UNSIGNED.
    LINKAGE SECTION.
        COPY DD-NBT-DECODER REPLACING LEADING ==NBT-DECODER== BY ==LK==.
        01 LK-BUFFER            PIC X ANY LENGTH.
        01 LK-TAG-NAME          PIC X ANY LENGTH.
        01 LK-AT-END            BINARY-CHAR UNSIGNED.

    PROCEDURE DIVISION USING LK-STATE LK-BUFFER LK-TAG-NAME LK-AT-END.
        PERFORM UNTIL EXIT
            CALL "NbtDecode-Peek" USING LK-STATE LK-BUFFER LK-AT-END TAG-NAME NAME-LEN
            IF LK-AT-END > 0
                GOBACK
            END-IF
            IF TAG-NAME(1:NAME-LEN) = LK-TAG-NAME
                EXIT PERFORM
            END-IF
            CALL "NbtDecode-Skip" USING LK-STATE LK-BUFFER
        END-PERFORM
        MOVE 0 TO LK-AT-END
        GOBACK.

    END PROGRAM SkipUntilTag.

    *> --- SkipRemainingTags ---
    *> A utility procedure to skip all remaining tags in a compound.
    IDENTIFICATION DIVISION.
    PROGRAM-ID. SkipRemainingTags.

    DATA DIVISION.
    WORKING-STORAGE SECTION.
        01 AT-END               BINARY-CHAR UNSIGNED.
        01 TAG-NAME             PIC X(256).
        01 NAME-LEN             BINARY-LONG UNSIGNED.
    LINKAGE SECTION.
        COPY DD-NBT-DECODER REPLACING LEADING ==NBT-DECODER== BY ==LK==.
        01 LK-BUFFER            PIC X ANY LENGTH.

    PROCEDURE DIVISION USING LK-STATE LK-BUFFER.
        PERFORM UNTIL EXIT
            CALL "NbtDecode-Peek" USING LK-STATE LK-BUFFER AT-END TAG-NAME NAME-LEN
            IF AT-END > 0
                GOBACK
            END-IF
            CALL "NbtDecode-Skip" USING LK-STATE LK-BUFFER
        END-PERFORM
        GOBACK.

    END PROGRAM SkipRemainingTags.

END PROGRAM World-LoadChunk.

*> --- World-EnsureChunk ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-EnsureChunk.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 IO-FAILURE           BINARY-CHAR UNSIGNED.
    *> World data
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-CHUNK-X           BINARY-LONG.
    01 LK-CHUNK-Z           BINARY-LONG.
    01 LK-CHUNK-INDEX       BINARY-LONG UNSIGNED.

PROCEDURE DIVISION USING LK-CHUNK-X LK-CHUNK-Z LK-CHUNK-INDEX.
    *> attempt to find the chunk
    CALL "World-FindChunkIndex" USING LK-CHUNK-X LK-CHUNK-Z LK-CHUNK-INDEX
    IF LK-CHUNK-INDEX > 0
        GOBACK
    END-IF
    *> not found, load or generate
    CALL "World-LoadChunk" USING LK-CHUNK-X LK-CHUNK-Z IO-FAILURE
    IF IO-FAILURE NOT = 0
        DISPLAY "Generating chunk: " LK-CHUNK-X " " LK-CHUNK-Z
        MOVE 0 TO IO-FAILURE
        CALL "World-GenerateChunk" USING LK-CHUNK-X LK-CHUNK-Z
    END-IF
    *> find the chunk again
    CALL "World-FindChunkIndex" USING LK-CHUNK-X LK-CHUNK-Z LK-CHUNK-INDEX
    GOBACK.

END PROGRAM World-EnsureChunk.

*> --- World-UnloadChunks ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-UnloadChunks.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    01 CHUNK-BLOCK-X        BINARY-LONG.
    01 CHUNK-BLOCK-Z        BINARY-LONG.
    01 MIN-DISTANCE         BINARY-LONG.
    01 PLAYER-INDEX         BINARY-LONG UNSIGNED.
    *> World data
    COPY DD-WORLD.
    *> Player data
    COPY DD-PLAYERS.
LINKAGE SECTION.
    01 LK-VIEW-DISTANCE     BINARY-LONG UNSIGNED.
    01 LK-FAILURE           BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-VIEW-DISTANCE LK-FAILURE.
    MOVE 0 TO LK-FAILURE
    PERFORM VARYING CHUNK-INDEX FROM 1 BY 1 UNTIL CHUNK-INDEX > WORLD-CHUNK-COUNT
        IF WORLD-CHUNK-PRESENT(CHUNK-INDEX) > 0
            COMPUTE CHUNK-BLOCK-X = WORLD-CHUNK-X(CHUNK-INDEX) * 16 + 8
            COMPUTE CHUNK-BLOCK-Z = WORLD-CHUNK-Z(CHUNK-INDEX) * 16 + 8
            *> Compute the minimum distance to any player on any axis
            MOVE 1000000 TO MIN-DISTANCE
            PERFORM VARYING PLAYER-INDEX FROM 1 BY 1 UNTIL PLAYER-INDEX > MAX-PLAYERS
                IF PLAYER-CLIENT(PLAYER-INDEX) > 0
                    COMPUTE MIN-DISTANCE = FUNCTION MIN(MIN-DISTANCE, FUNCTION ABS(CHUNK-BLOCK-X - PLAYER-X(PLAYER-INDEX)))
                    COMPUTE MIN-DISTANCE = FUNCTION MIN(MIN-DISTANCE, FUNCTION ABS(CHUNK-BLOCK-Z - PLAYER-Z(PLAYER-INDEX)))
                END-IF
            END-PERFORM
            *> If the chunk is outside the view distance + 2 (for tolerance against thrashing), unload it
            COMPUTE MIN-DISTANCE = MIN-DISTANCE / 16 - LK-VIEW-DISTANCE
            IF MIN-DISTANCE > 2
                IF WORLD-CHUNK-DIRTY(CHUNK-INDEX) > 0
                    CALL "World-SaveChunk" USING CHUNK-INDEX LK-FAILURE
                    IF LK-FAILURE > 0
                        MOVE 1 TO LK-FAILURE
                        GOBACK
                    END-IF
                END-IF
                MOVE 0 TO WORLD-CHUNK-PRESENT(CHUNK-INDEX)
            END-IF
        END-IF
    END-PERFORM
    GOBACK.

END PROGRAM World-UnloadChunks.

*> --- World-SaveLevel ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-SaveLevel.

DATA DIVISION.
WORKING-STORAGE SECTION.
    *> File name and data
    01 LEVEL-FILE-NAME      PIC X(255)              VALUE "save/level.dat".
    01 ERRNO                BINARY-LONG.
    01 NBT-BUFFER           PIC X(64000).
    01 NBT-BUFFER-LENGTH    BINARY-LONG UNSIGNED.
    01 COMPRESSED-BUFFER    PIC X(64000).
    01 COMPRESSED-LENGTH    BINARY-LONG UNSIGNED.
    *> Temporary variables
    01 TAG-NAME             PIC X(256).
    01 NAME-LEN             BINARY-LONG UNSIGNED.
    *> World data
    COPY DD-WORLD.
LOCAL-STORAGE SECTION.
    COPY DD-NBT-ENCODER.
LINKAGE SECTION.
    01 LK-FAILURE           BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-FAILURE.
    MOVE 0 TO LK-FAILURE
    MOVE ALL X"00" TO NBT-BUFFER

    *> root tag
    MOVE 1 TO NBT-ENCODER-OFFSET
    CALL "NbtEncode-RootCompound" USING NBT-ENCODER-STATE NBT-BUFFER

    *> "Data" tag
    MOVE "Data" TO TAG-NAME
    MOVE 4 TO NAME-LEN
    CALL "NbtEncode-Compound" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN

    *> "Time": world age
    MOVE "Time" TO TAG-NAME
    MOVE 4 TO NAME-LEN
    CALL "NbtEncode-Long" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN WORLD-AGE

    *> "DayTime": world time
    MOVE "DayTime" TO TAG-NAME
    MOVE 7 TO NAME-LEN
    CALL "NbtEncode-Long" USING NBT-ENCODER-STATE NBT-BUFFER TAG-NAME NAME-LEN WORLD-TIME

    *> end "Data" and root tags
    CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER
    CALL "NbtEncode-EndCompound" USING NBT-ENCODER-STATE NBT-BUFFER

    *> write the data to disk in gzip-compressed form
    COMPUTE NBT-BUFFER-LENGTH = NBT-ENCODER-OFFSET - 1
    MOVE LENGTH OF COMPRESSED-BUFFER TO COMPRESSED-LENGTH
    CALL "GzipCompress" USING NBT-BUFFER NBT-BUFFER-LENGTH COMPRESSED-BUFFER COMPRESSED-LENGTH GIVING ERRNO
    IF ERRNO NOT = 0
        MOVE 1 TO LK-FAILURE
        GOBACK
    END-IF
    CALL "Files-WriteAll" USING LEVEL-FILE-NAME COMPRESSED-BUFFER COMPRESSED-LENGTH LK-FAILURE

    GOBACK.

END PROGRAM World-SaveLevel.

*> --- World-LoadLevel ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-LoadLevel.

DATA DIVISION.
WORKING-STORAGE SECTION.
    *> File name and data
    01 LEVEL-FILE-NAME          PIC X(255)              VALUE "save/level.dat".
    01 ERRNO                    BINARY-LONG.
    01 COMPRESSED-BUFFER        PIC X(64000).
    01 COMPRESSED-LENGTH        BINARY-LONG UNSIGNED.
    01 NBT-BUFFER               PIC X(64000).
    01 NBT-BUFFER-LENGTH        BINARY-LONG UNSIGNED.
    *> Temporary variables
    01 STR-VALUE                PIC X(256).
    01 STR-LEN                  BINARY-LONG UNSIGNED.
    01 AT-END                   BINARY-CHAR UNSIGNED.
    *> World data
    COPY DD-WORLD.
LOCAL-STORAGE SECTION.
    COPY DD-NBT-DECODER.
LINKAGE SECTION.
    01 LK-FAILURE           BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-FAILURE.
    MOVE 0 TO LK-FAILURE

    *> Set defaults
    MOVE 0 TO WORLD-AGE
    MOVE 0 TO WORLD-TIME

    *> Read the file
    CALL "Files-ReadAll" USING LEVEL-FILE-NAME NBT-BUFFER NBT-BUFFER-LENGTH LK-FAILURE
    IF LK-FAILURE NOT = 0 OR NBT-BUFFER-LENGTH = 0
        GOBACK
    END-IF

    *> Check for the gzip magic number, and decompress if present
    IF NBT-BUFFER(1:2) = X"1F8B"
        MOVE NBT-BUFFER(1:NBT-BUFFER-LENGTH) TO COMPRESSED-BUFFER(1:NBT-BUFFER-LENGTH)
        MOVE NBT-BUFFER-LENGTH TO COMPRESSED-LENGTH
        MOVE LENGTH OF NBT-BUFFER TO NBT-BUFFER-LENGTH
        CALL "GzipDecompress" USING COMPRESSED-BUFFER COMPRESSED-LENGTH NBT-BUFFER NBT-BUFFER-LENGTH GIVING ERRNO
        IF ERRNO NOT = 0
            MOVE 1 TO LK-FAILURE
            GOBACK
        END-IF
    END-IF

    *> root tag containing the "Data" compound
    MOVE 1 TO NBT-DECODER-OFFSET
    CALL "NbtDecode-RootCompound" USING NBT-DECODER-STATE NBT-BUFFER
    CALL "NbtDecode-Compound" USING NBT-DECODER-STATE NBT-BUFFER

    PERFORM UNTIL EXIT
        CALL "NbtDecode-Peek" USING NBT-DECODER-STATE NBT-BUFFER AT-END STR-VALUE STR-LEN
        IF AT-END > 0
            EXIT PERFORM
        END-IF
        EVALUATE STR-VALUE(1:STR-LEN)
            WHEN "Time"
                CALL "NbtDecode-Long" USING NBT-DECODER-STATE NBT-BUFFER WORLD-AGE
            WHEN "DayTime"
                CALL "NbtDecode-Long" USING NBT-DECODER-STATE NBT-BUFFER WORLD-TIME
            WHEN OTHER
                CALL "NbtDecode-Skip" USING NBT-DECODER-STATE NBT-BUFFER
        END-EVALUATE
    END-PERFORM

    *> end of "Data" and root tags
    CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER
    CALL "NbtDecode-EndCompound" USING NBT-DECODER-STATE NBT-BUFFER

    GOBACK.

END PROGRAM World-LoadLevel.

*> --- World-Save ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-Save.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    *> World data
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-FAILURE           BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-FAILURE.
    *> Create directories. Ignore errors, as they are likely to be caused by the directories already existing.
    CALL "CBL_CREATE_DIR" USING "save"
    CALL "CBL_CREATE_DIR" USING "save/region"

    *> Save world metadata
    CALL "World-SaveLevel" USING LK-FAILURE
    IF LK-FAILURE > 0
        GOBACK
    END-IF

    *> Save dirty chunks
    PERFORM VARYING CHUNK-INDEX FROM 1 BY 1 UNTIL CHUNK-INDEX > WORLD-CHUNK-COUNT
        IF WORLD-CHUNK-PRESENT(CHUNK-INDEX) > 0 AND WORLD-CHUNK-DIRTY(CHUNK-INDEX) > 0
            CALL "World-SaveChunk" USING CHUNK-INDEX LK-FAILURE
            IF LK-FAILURE > 0
                GOBACK
            END-IF
        END-IF
    END-PERFORM

    GOBACK.

END PROGRAM World-Save.

*> --- World-Load ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-Load.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    01 CHUNK-X              BINARY-LONG.
    01 CHUNK-Z              BINARY-LONG.
    01 IO-FAILURE           BINARY-CHAR UNSIGNED.
    01 SAVE-REQUIRED        BINARY-CHAR UNSIGNED.
    *> World data
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-FAILURE           BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-FAILURE.
    MOVE 0 TO SAVE-REQUIRED
    MOVE 0 TO LK-FAILURE

    *> Load the world metadata
    CALL "World-LoadLevel" USING IO-FAILURE
    IF IO-FAILURE > 0
        DISPLAY "Unable to read world data, generating a new world"
        MOVE 0 TO IO-FAILURE
        MOVE 1 TO SAVE-REQUIRED
    END-IF

    *> Mark all chunks as absent
    PERFORM VARYING CHUNK-INDEX FROM 1 BY 1 UNTIL CHUNK-INDEX > WORLD-CHUNK-COUNT
        MOVE 0 TO WORLD-CHUNK-PRESENT(CHUNK-INDEX)
    END-PERFORM

    *> Load a 3x3 spawn area. If necessary, generate new chunks.
    PERFORM VARYING CHUNK-Z FROM -1 BY 1 UNTIL CHUNK-Z > 1
        PERFORM VARYING CHUNK-X FROM -1 BY 1 UNTIL CHUNK-X > 1
            CALL "World-LoadChunk" USING CHUNK-X CHUNK-Z IO-FAILURE
            IF IO-FAILURE NOT = 0
                DISPLAY "Generating chunk: " CHUNK-X " " CHUNK-Z
                MOVE 0 TO IO-FAILURE
                CALL "World-GenerateChunk" USING CHUNK-X CHUNK-Z
                MOVE 1 TO SAVE-REQUIRED
            END-IF
        END-PERFORM
    END-PERFORM

    *> Save the world if necessary
    IF SAVE-REQUIRED > 0
        CALL "World-Save" USING LK-FAILURE
    END-IF

    GOBACK.

END PROGRAM World-Load.

*> --- World-CheckBounds ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-CheckBounds.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-POSITION.
        02 LK-X                 BINARY-LONG.
        02 LK-Y                 BINARY-LONG.
        02 LK-Z                 BINARY-LONG.
    01 LK-RESULT            BINARY-CHAR UNSIGNED.

PROCEDURE DIVISION USING LK-POSITION LK-RESULT.
    IF LK-Y < -64 OR LK-Y > 319 THEN
        MOVE 1 TO LK-RESULT
    ELSE
        MOVE 0 TO LK-RESULT
    END-IF
    GOBACK.

END PROGRAM World-CheckBounds.

*> --- World-GetBlock ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-GetBlock.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.
LOCAL-STORAGE SECTION.
    01 CHUNK-X              BINARY-LONG.
    01 CHUNK-Z              BINARY-LONG.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    01 SECTION-INDEX        BINARY-LONG UNSIGNED.
    01 BLOCK-INDEX          BINARY-LONG UNSIGNED.
LINKAGE SECTION.
    01 LK-POSITION.
        02 LK-X                 BINARY-LONG.
        02 LK-Y                 BINARY-LONG.
        02 LK-Z                 BINARY-LONG.
    01 LK-BLOCK-ID          BINARY-LONG UNSIGNED.

PROCEDURE DIVISION USING LK-POSITION LK-BLOCK-ID.
    *> find the chunk
    DIVIDE LK-X BY 16 GIVING CHUNK-X ROUNDED MODE IS TOWARD-LESSER
    DIVIDE LK-Z BY 16 GIVING CHUNK-Z ROUNDED MODE IS TOWARD-LESSER
    CALL "World-FindChunkIndex" USING CHUNK-X CHUNK-Z CHUNK-INDEX
    IF CHUNK-INDEX = 0
        MOVE 0 TO LK-BLOCK-ID
        GOBACK
    END-IF
    *> compute the block index
    COMPUTE SECTION-INDEX = (LK-Y + 64) / 16 + 1
    COMPUTE BLOCK-INDEX = ((FUNCTION MOD(LK-Y + 64, 16)) * 16 + (FUNCTION MOD(LK-Z, 16))) * 16 + (FUNCTION MOD(LK-X, 16)) + 1
    MOVE WORLD-BLOCK-ID(CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX) TO LK-BLOCK-ID
    GOBACK.

END PROGRAM World-GetBlock.

*> --- World-SetBlock ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-SetBlock.

DATA DIVISION.
WORKING-STORAGE SECTION.
    01 C-WORLD-EVENT-BLOCK-BREAK    BINARY-LONG UNSIGNED    VALUE 2001.
    COPY DD-WORLD.
    COPY DD-CLIENT-STATES.
    COPY DD-CLIENTS.
    01 CHUNK-X              BINARY-LONG.
    01 CHUNK-Z              BINARY-LONG.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    01 SECTION-INDEX        BINARY-LONG UNSIGNED.
    01 BLOCK-IN-CHUNK-INDEX BINARY-LONG UNSIGNED.
    01 BLOCK-INDEX          BINARY-LONG UNSIGNED.
    01 PREVIOUS-BLOCK-ID    BINARY-LONG UNSIGNED.
    01 IS-SAME-BLOCK-TYPE   BINARY-CHAR UNSIGNED.
    01 CLIENT-ID            BINARY-LONG UNSIGNED.
LINKAGE SECTION.
    *> The client that performed the action, to avoid playing sounds/particles for them
    01 LK-CLIENT            BINARY-LONG UNSIGNED.
    01 LK-POSITION.
        02 LK-X                 BINARY-LONG.
        02 LK-Y                 BINARY-LONG.
        02 LK-Z                 BINARY-LONG.
    01 LK-BLOCK-ID          BINARY-LONG UNSIGNED.

PROCEDURE DIVISION USING LK-CLIENT LK-POSITION LK-BLOCK-ID.
    *> Find the chunk, section, and block indices
    DIVIDE LK-X BY 16 GIVING CHUNK-X ROUNDED MODE IS TOWARD-LESSER
    DIVIDE LK-Z BY 16 GIVING CHUNK-Z ROUNDED MODE IS TOWARD-LESSER
    CALL "World-FindChunkIndex" USING CHUNK-X CHUNK-Z CHUNK-INDEX
    IF CHUNK-INDEX = 0
        GOBACK
    END-IF
    COMPUTE SECTION-INDEX = (LK-Y + 64) / 16 + 1
    COMPUTE BLOCK-INDEX = ((FUNCTION MOD(LK-Y + 64, 16)) * 16 + (FUNCTION MOD(LK-Z, 16))) * 16 + (FUNCTION MOD(LK-X, 16)) + 1

    *> Skip if identical to the current block
    MOVE WORLD-BLOCK-ID(CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX) TO PREVIOUS-BLOCK-ID
    IF PREVIOUS-BLOCK-ID = LK-BLOCK-ID
        GOBACK
    END-IF

    *> Check whether the block is becoming air or non-air
    EVALUATE TRUE
        WHEN LK-BLOCK-ID = 0
            SUBTRACT 1 FROM WORLD-SECTION-NON-AIR(CHUNK-INDEX, SECTION-INDEX)
        WHEN PREVIOUS-BLOCK-ID = 0
            ADD 1 TO WORLD-SECTION-NON-AIR(CHUNK-INDEX, SECTION-INDEX)
    END-EVALUATE

    *> Set the block and mark the chunk as dirty
    MOVE LK-BLOCK-ID TO WORLD-BLOCK-ID(CHUNK-INDEX, SECTION-INDEX, BLOCK-INDEX)
    MOVE 1 TO WORLD-CHUNK-DIRTY(CHUNK-INDEX)

    *> If the block is changing to a different type (not just state), remove any block entity
    IF PREVIOUS-BLOCK-ID NOT = 0
        CALL "Blocks-CompareBlockType" USING PREVIOUS-BLOCK-ID LK-BLOCK-ID IS-SAME-BLOCK-TYPE
        IF IS-SAME-BLOCK-TYPE = 0
            COMPUTE BLOCK-IN-CHUNK-INDEX = ((LK-Y + 64) * 16 + (FUNCTION MOD(LK-Z, 16))) * 16 + (FUNCTION MOD(LK-X, 16)) + 1
            IF WORLD-BLOCK-ENTITY-ID(CHUNK-INDEX, BLOCK-IN-CHUNK-INDEX) >= 0
                MOVE -1 TO WORLD-BLOCK-ENTITY-ID(CHUNK-INDEX, BLOCK-IN-CHUNK-INDEX)
                SUBTRACT 1 FROM WORLD-BLOCK-ENTITY-COUNT(CHUNK-INDEX)
            END-IF
        END-IF
    END-IF

    *> Notify clients
    PERFORM VARYING CLIENT-ID FROM 1 BY 1 UNTIL CLIENT-ID > MAX-CLIENTS
        IF CLIENT-PRESENT(CLIENT-ID) = 1 AND CLIENT-STATE(CLIENT-ID) = CLIENT-STATE-PLAY
            CALL "SendPacket-BlockUpdate" USING CLIENT-ID LK-POSITION LK-BLOCK-ID
            *> play block break sound and particles
            IF CLIENT-ID NOT = LK-CLIENT AND LK-BLOCK-ID = 0
                CALL "SendPacket-WorldEvent" USING CLIENT-ID C-WORLD-EVENT-BLOCK-BREAK LK-POSITION PREVIOUS-BLOCK-ID
            END-IF
        END-IF
    END-PERFORM

    GOBACK.

END PROGRAM World-SetBlock.

*> --- World-SetBlockEntity ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-SetBlockEntity.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.
    COPY DD-CLIENT-STATES.
    COPY DD-CLIENTS.
    01 CHUNK-X              BINARY-LONG.
    01 CHUNK-Z              BINARY-LONG.
    01 CHUNK-INDEX          BINARY-LONG UNSIGNED.
    01 BLOCK-IN-CHUNK-INDEX BINARY-LONG UNSIGNED.
    01 CLIENT-ID            BINARY-LONG UNSIGNED.
    *> TODO support entity data
    *> Currently, only block entities without any data (= empty compound tag) are supported.
    01 ENTITY-DATA          PIC X(2)                        VALUE X"0A00".
    01 ENTITY-DATA-LENGTH   BINARY-LONG UNSIGNED            VALUE 2.
LINKAGE SECTION.
    01 LK-POSITION.
        02 LK-X                 BINARY-LONG.
        02 LK-Y                 BINARY-LONG.
        02 LK-Z                 BINARY-LONG.
    01 LK-BLOCK-ENTITY-ID   BINARY-LONG.

PROCEDURE DIVISION USING LK-POSITION LK-BLOCK-ENTITY-ID.
    *> Find the chunk and block indices
    DIVIDE LK-X BY 16 GIVING CHUNK-X ROUNDED MODE IS TOWARD-LESSER
    DIVIDE LK-Z BY 16 GIVING CHUNK-Z ROUNDED MODE IS TOWARD-LESSER
    CALL "World-FindChunkIndex" USING CHUNK-X CHUNK-Z CHUNK-INDEX
    IF CHUNK-INDEX = 0
        GOBACK
    END-IF
    COMPUTE BLOCK-IN-CHUNK-INDEX = ((LK-Y + 64) * 16 + (FUNCTION MOD(LK-Z, 16))) * 16 + (FUNCTION MOD(LK-X, 16)) + 1

    IF WORLD-BLOCK-ENTITY-ID(CHUNK-INDEX, BLOCK-IN-CHUNK-INDEX) >= 0
        SUBTRACT 1 FROM WORLD-BLOCK-ENTITY-COUNT(CHUNK-INDEX)
    END-IF

    *> Set the block entity ID
    MOVE LK-BLOCK-ENTITY-ID TO WORLD-BLOCK-ENTITY-ID(CHUNK-INDEX, BLOCK-IN-CHUNK-INDEX)
    ADD 1 TO WORLD-BLOCK-ENTITY-COUNT(CHUNK-INDEX)

    *> Notify clients
    PERFORM VARYING CLIENT-ID FROM 1 BY 1 UNTIL CLIENT-ID > MAX-CLIENTS
        IF CLIENT-PRESENT(CLIENT-ID) = 1 AND CLIENT-STATE(CLIENT-ID) = CLIENT-STATE-PLAY
            CALL "SendPacket-BlockEntityData" USING CLIENT-ID LK-POSITION LK-BLOCK-ENTITY-ID ENTITY-DATA ENTITY-DATA-LENGTH
        END-IF
    END-PERFORM

    GOBACK.

END PROGRAM World-SetBlockEntity.

*> --- World-GetAge ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-GetAge.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-AGE               BINARY-LONG-LONG.

PROCEDURE DIVISION USING LK-AGE.
    MOVE WORLD-AGE TO LK-AGE
    GOBACK.

END PROGRAM World-GetAge.

*> --- World-GetTime ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-GetTime.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-TIME              BINARY-LONG-LONG.

PROCEDURE DIVISION USING LK-TIME.
    MOVE WORLD-TIME TO LK-TIME
    GOBACK.

END PROGRAM World-GetTime.

*> --- World-SetTime ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-SetTime.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.
LINKAGE SECTION.
    01 LK-TIME              BINARY-LONG-LONG.

PROCEDURE DIVISION USING LK-TIME.
    MOVE LK-TIME TO WORLD-TIME
    GOBACK.

END PROGRAM World-SetTime.

*> --- World-UpdateAge ---
IDENTIFICATION DIVISION.
PROGRAM-ID. World-UpdateAge.

DATA DIVISION.
WORKING-STORAGE SECTION.
    COPY DD-WORLD.

PROCEDURE DIVISION.
    ADD 1 TO WORLD-AGE
    ADD 1 TO WORLD-TIME
    GOBACK.

END PROGRAM World-UpdateAge.
