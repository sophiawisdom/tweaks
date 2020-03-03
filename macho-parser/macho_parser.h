//
//  macho_parser.h
//  macho-parser
//
//  Created by Sophia Wisdom on 3/1/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

#ifndef macho_parser_h
#define macho_parser_h

#include <stdio.h>

uint64_t getSymbolOffset(const char *dylib, char *symbol);

#endif /* macho_parser_h */
