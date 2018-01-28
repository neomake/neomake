#!/usr/bin/python3
import sys
import json
import argparse
from urllib.request import urlopen
from urllib.parse import urlencode


def process_match(m, input_text):
    offset = m['offset']
    length = m['length']
    # rule_id = m['rule']['id']
    rule_type = m['rule']['issueType']
    message_long = m['message']
    # message_short = m['shortMessage']

    error = False

    word = input_text[offset:offset+length]
    l_start = input_text.rfind('\n', 0, offset) + 1  # Skip the newline
    l_end = input_text.find('\n', offset)
    # `find` and `rfind` return `-1` when not found, which does the right thing
    line = input_text[l_start:l_end]
    line_num = input_text.count('\n', 0, offset) + 1
    column_num = offset - input_text.rfind('\n', 0, offset)  # In characters

    bytes_line = line.encode()
    bytes_word = word.encode()
    # Column Number and Lenght are interpreted as bytes in vim
    try:
        column_num = bytes_line.index(bytes_word, column_num - 1) + 1
    except ValueError as e:
        column_num = -1
    length = len(bytes_word)

    if rule_type == 'misspelling':
        error = True

        replacements = m['replacements'][:3]  # Top 3
        message = '"%s"' % word
        if len(replacements) > 0:
            replacement_values = ['"%s"' % e['value']
                                  for e in replacements]
            message += ' => ' + '|'.join(replacement_values)
    else:
        message = message_long

    if error:
        str_type = 'E'
    else:
        str_type = 'W'

    return {
        'text': message,
        'lnum': line_num,
        'col': column_num,
        'length': length,
        'type': str_type,
    }


parser = argparse.ArgumentParser(description='LanguageTool NeoMake wrapper')
parser.add_argument('server',
                    help='The server root URI')
parser.add_argument('language',
                    help='Language to check. Use `auto` to auto select')
parser.add_argument('filename',
                    help='Filename to check')
parser.add_argument('--motherTongue')
parser.add_argument('--preferredVariants', action='append')
args = parser.parse_args()

if args.filename == '-':
    input_file = sys.stdin
else:
    input_file = open(args.filename, 'r')

input_text = ''.join(input_file.readlines())

request_url = '%s/v2/check' % args.server
request_data = {
    'language': args.language,
    'text': input_text,
}
if args.motherTongue:
    request_data['motherTongue'] = args.motherTongue
if args.preferredVariants and args.language == 'auto':
    request_data['preferredVariants'] = ','.join(args.preferredVariants)

output = '[]'
with urlopen(request_url, data=urlencode(request_data).encode()) as r:
    charset = r.info().get_content_charset() or 'UTF-8'
    output = r.read().decode(charset)

output_json = json.loads(output)

result = [process_match(m, input_text) for m in output_json['matches']]

json.dump(result, sys.stdout)
