#!/usr/bin/env python

"""A iperf2 UDP performance result cleanner.

scrubberU translates test result log into readable CSV file.
"""

import os
import datetime
import argparse
from utils import HWLogging


def translator(result_file, datetime_obj, load):
    """Translate each line of result file into a comma seperated string.

    Return a generator, NOT a list or tuple.
    Raw format of a line of result file sample:
    [
        '[', '3]',
        '20.00-30.00', 'sec',
        '187', 'MBytes',
        '157', 'Mbits/sec',
        '0.009', 'ms',
        '0/1535998',
        '(0%)',
        '0.068/', '0.040/', '0.990/', '0.041', 'ms',
        '153601', 'pps'
    ]

    Translated sample:
    "02/27/2018 10:23:54,187,157,0,1535998,0.068,0.040,0.990,0.041,153601"
    """
    ESCAPED_TIME_ELAPSED = '360'
    with open(result_file) as f:
        for line in f:
            fields = line.strip().split()
            if len(fields) > 15 and ESCAPED_TIME_ELAPSED not in fields[2]:
                logger.debug("Parsed line fields - {0}.".format(fields))
                # deal with date time - 20.00-30.00
                elapsed = int(float(fields[2].strip().split('-')[-1].strip()))
                timestamp = datetime_obj + datetime.timedelta(seconds=elapsed)
                logger.debug("Timestamp {0}.".format(
                    timestamp.strftime('%m/%d/%Y %H:%M:%S'))
                    )

                # solid fields format in output string
                timestamp_str = timestamp.strftime('%m/%d/%Y %H:%M:%S')
                transfer = fields[4].strip()
                bandwidth = fields[6].strip()
                lost = fields[10].split('/')[0].strip()
                total = fields[10].split('/')[1].strip()
                pps = fields[-2].strip()

                # different scenarios:
                # '0.068/', '0.040/', '0.990/', '0.041', 'ms'
                # '0.002/-0.030/', '2.248/', '0.059', 'ms'
                # '0.072/', '0.000/10.274/', '0.324', 'ms'
                latency = ''.join(fields[12:-3]).split('/')
                latency_avg, latency_min, latency_max, latency_stdev = latency

                # yielded string fields
                yield "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}, {10}".format(
                    timestamp_str, load, transfer, bandwidth, lost, total,
                    latency_avg, latency_min, latency_max, latency_stdev, pps
                )


def list_files(result_path, client_or_server):
    """Put all client/server result file name into a list."""
    # best alternative for switch/case
    pat_endswith = {
        'client': 'client.iperf',
        'server': 'server.iperf'
    }
    # return a generator instead of a list or tuple to save memory
    return (
        f for f in os.listdir(result_path)
        if f.endswith(pat_endswith[client_or_server])
        )


def sort_by_bandwidth(generator):
    """Sort result file name by bandwidth.

    Result file name sample: run1-130M-client.iperf
    """
    return sorted(
        generator,
        key=lambda fn: int(fn.strip().split('-')[1].strip()[:-1])
        )


def formated_file_list(result_path, generator):
    """Sort result file first, than insert path before file name."""
    return map(
        lambda x: os.path.join(result_path, x),
        sort_by_bandwidth(generator)
        )


def scrubber(result_path, c_or_s):
    """Parse result file, then save parse output to CSV file."""
    # get a list of client result file name
    client_fn_raw = list_files(result_path, c_or_s)
    logger.debug(
        "All client result file name: {0}.".format(client_fn_raw)
        )

    # sort and format file name
    client_files = formated_file_list(result_path, client_fn_raw)
    logger.info("Final log file - {0}".format(client_files))

    # dealing with file content
    for file_name in client_files:
        # generate csv file name coming from result file name
        # test/files/run1-150M-client.iperf
        # => test/files/run1-client.iperf.csv
        tmp_name_parts = os.path.basename(file_name).split('-')
        load = tmp_name_parts[1][:-1]
        tmp_name_string = "{0}-{1}.csv".format(
            tmp_name_parts[0],
            tmp_name_parts[2]
            )
        csv_file_name = os.path.join(
            os.path.dirname(file_name),
            tmp_name_string
        )
        logger.info("CSV file name - {0}".format(csv_file_name))

        # get timestamp from client result file
        # server result file does not contain timestamp
        # needs to get it from client result file with the same bandwidth
        if 'server.iperf' in file_name:
            date_file = file_name.replace('server', 'client')
        else:
            date_file = file_name
        with open(date_file) as f:
            datetime_str = f.readline().strip()
            logger.debug("Raw timestamp is {0}.".format(datetime_str))
        datetime_obj = datetime.datetime.strptime(
            datetime_str,
            '%Y%m%d_%H%M%S'
            )
        logger.info("Timestamp object is {0}.".format(datetime_obj))

        # write parsed content into disk.
        with open(csv_file_name, 'a') as f:
            for x in translator(file_name, datetime_obj, load):
                f.write("{0}\n".format(x))


def main(scrubber_args):
    """Script starts from here."""
    # print all avaliable arguments passed in.
    result_path = scrubber_args.result_path
    logger.info("Start cleaning result file in: {0}.".format(result_path))
    scrubber(result_path, 'client')
    scrubber(result_path, 'server')


if __name__ == '__main__':
    logger = HWLogging.Logger(__file__, '/tmp/').logger
    parser = argparse.ArgumentParser(
        description='A iperf2 UDP performance result cleanner.')
    parser.add_argument(
        "result_path",
        metavar="result-file-directory",
        type=str,
        help="Absolute test result file path."
        )
    scrubber_args = parser.parse_args()

    main(scrubber_args)
