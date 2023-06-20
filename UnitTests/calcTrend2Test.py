import numpy as np
import glob
import os

os.environ['testMode'] = '1'

from calcTrend2 import *

def getOptions():
    usage = "usage: %prog [options]"
    parser = OptionParser(usage=usage)
    parser.add_option("-d", "--datapath", dest="dataPath",  default = './',  type="string", 
                      help="Data file path. Default is './'", metavar="DATA_PATH")
                      
    parser.add_option("-r", "--reportpath", dest="reportPath",  default = './',  type="string", 
                      help="Path to store formance report. Default is './'", metavar="TARGET_PATH")
                      
    parser.add_option("-t", "--threshold", dest="threshold", default=5.0, type="float", 
                      help="Trend threshold to determine significant increasing/decreasing trend. Default is 5.0%"
                      , metavar="THRESHOLD")

    parser.add_option("--pdfReport", dest="pdfReport", action="store_true", default = False, 
                      help="Enable PDF reports generation."
                      , metavar="PDF_REPORT")
                      
    parser.add_option("-v", "--verbose", dest="verbose", default=False, action="store_true", 
                      help="Show more info. Default is False"
                      , metavar="VERBOSE")
                      
    parser.add_option("--movingAverageWindow1", dest="movingAverageWindow1", default=7, type="int", 
                      help="Moving average 1 window size. Default is 7 days"
                      , metavar="MOVINGAVERAGEWINDOW1")

    parser.add_option("--disableMovingAverage1", dest="disableMovingAverage1", default=False, action="store_true", 
                      help="Disable to draw Moving average 1. Default is False"
                      , metavar="DISABLEMOVINGAVERAGE1")
                      
    parser.add_option("--movingAverageWindow2", dest="movingAverageWindow2", default=30, type="int", 
                      help="Moving average 2 window size. Default is 30 days"
                      , metavar="MOVINGAVERAGEWINDOW2")
                      
    parser.add_option("--disableMovingAverage2", dest="disableMovingAverage2", default=False, action="store_true", 
                      help="Disable to draw Moving average 2. Default is False"
                      , metavar="DISABLEMOVINGAVERAGE2")
                      
    parser.add_option("--enableSigma", dest="enableSigma", default=False, action="store_true", 
                      help="Enable to draw Sigma range. Default is False"
                      , metavar="ENABLESIGMA")
                    
    parser.add_option("--enableMin", dest="enableMin", default=False, action="store_true", 
                      help="Enable to draw Min values. Default is False"
                      , metavar="ENABLEMIN")
                      
    parser.add_option("--enableMax", dest="enableMax", default=False, action="store_true", 
                      help="Enable to draw Max values. Default is False"
                      , metavar="ENABLEMAX")

    parser.add_option("--enableTestPlotGeneration", dest="enableTestPlotGeneration", default=False, action="store_true", 
                      help="Enable to generate diagram for each test case. Default is False"
                      , metavar="ENABLETESTPLOTGENERATION")

    (options, args) = parser.parse_args()

    if options.dataPath == None:
        parser.print_help()
        return None
        
    return (options, args)
    
    
#
# Main
    
    
options = getOptions()

tr = TrendReport(options[0])

numSummaryFiles = len(glob.glob("perftest-*.summary"))
numCsvFiles = len(glob.glob("perftest-*.csv"))

tr.readData()
tr.processResults()

print("\n\nFILE CREATION TEST\n")

if len(glob.glob("perftest-*.summary")) - numSummaryFiles == 1: 
    print("Pass: Summary File Produced")
else:
    print("Error: Summary File Not Produced")

if len(glob.glob("perftest-*.csv")) - numCsvFiles == 1: 
    print("Pass: Csv File Produced")
else:
    print("Error: Csv File Not Produced")
    
print("\nCALCMOVINGAVERAGE TESTS\n")

inputs = [(2, [2, 3, 8]), (1, [1, 2, 3]), (4, [5, 8, 11, 7])]
expecteds = [[2, 2.5, 5.5], [1, 2, 3], [5, 6.5, 8, 7.75]]

i = 0
failed = 0

for input in inputs:
    averages = tr.calcMovingAverage(input[0], input[1])
    
    if averages != expecteds[i]:
        print("Error")
        print("Input:", input[0], input[1])
        print("Expected:", expecteds[i])
        print("Actual:", averages)
        failed = 1
    
    i += 1
    
if failed == 0:
    print("All tests passed!\n")

print("\nCALCTREND FUNCTION TEST\n")

inputs = [np.array([0.5, 2, 1]), np.array([10, 10, 10]), np.array([100, 50, 0.5])]
expecteds = ["increased", "unaltered", "decreased"] 
 
i = 0
failed = 0

for input in inputs:
    direction = tr.CalcTrend(input)['direction']
    
    if direction != expecteds[i]:
        print("Error")
        print("Input", inputs[i])
        print("Expected Direction", expecteds[i])
        print("Actual Direction", direction)
        failed = 1
    
    i += 1
        
if failed == 0:
    print("All tests passed!\n")
    
os.environ['testMode'] = '0'      

