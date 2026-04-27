local Utils=require("seq_utils")
Utils._NOTE_NAMES = {
    "C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"
}
Utils.SCALES = {}
Utils.SCALES.chromatic        = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
Utils.SCALES.major            = { 0, 2, 4, 5, 7, 9, 11 }
Utils.SCALES.naturalMinor     = { 0, 2, 3, 5, 7, 8, 10 }
Utils.SCALES.harmonicMinor    = { 0, 2, 3, 5, 7, 8, 11 }
Utils.SCALES.melodicMinor     = { 0, 2, 3, 5, 7, 9, 11 }
Utils.SCALES.dorian           = { 0, 2, 3, 5, 7, 9, 10 }
Utils.SCALES.phrygian         = { 0, 1, 3, 5, 7, 8, 10 }
Utils.SCALES.lydian           = { 0, 2, 4, 6, 7, 9, 11 }
Utils.SCALES.mixolydian       = { 0, 2, 4, 5, 7, 9, 10 }
Utils.SCALES.locrian          = { 0, 1, 3, 5, 6, 8, 10 }
Utils.SCALES.majorPentatonic  = { 0, 2, 4, 7, 9 }
Utils.SCALES.minorPentatonic  = { 0, 3, 5, 7, 10 }
Utils.SCALES.blues            = { 0, 3, 5, 6, 7, 10 }
Utils.SCALES.wholeTone        = { 0, 2, 4, 6, 8, 10 }
Utils.SCALES.diminished       = { 0, 2, 3, 5, 6, 8, 9, 11 }
Utils.SCALES.arabic           = { 0, 1, 4, 5, 7, 8, 11 }
Utils.SCALES.hungarianMinor   = { 0, 2, 3, 6, 7, 8, 11 }
