#!/usr/bin/env python

from reportlab.lib.pagesizes import A4, landscape, cm
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate
from reportlab.lib.units import mm
from reportlab.platypus.paragraph import Paragraph
from reportlab.lib.styles import getSampleStyleSheet #, ParagraphStyle
from reportlab.lib import colors
from reportlab.platypus.tables import *
from reportlab.platypus.flowables import PageBreak, Spacer


class PdfPerfReportGen(object):
    
    def __init__(self):
        self.styleSheet = getSampleStyleSheet()
        self.MARGIN_SIZE = 25 * mm
        self.PAGE_SIZE = A4              # Portrait
        self.PAGE_SIZE = landscape(A4) 
        self.story = []
        self.newTable()
        self.defaultHeaderData = [
                ['Test case','Last two run',  '', '', 'Last five run',  '', '',  'All runs', '' , '' ], 
                ['','Trend\nsec/run','Trend','%','Trend\nsec/run','Trend','%','Trend\nsec/run','Trend','%'],
            ]
        self.defaultHeaderStyle = [
                # Header
                ('SPAN',  (0, 0),  (0, 1)),
                ('VALIGN',  (0, 0),  (0, 1),  'MIDDLE'), 
                ('SPAN',  (1, 0),  (3, 0)),
                ('ALIGN',  (1, 0),  (3, 0),  'CENTER'), 
                ('SPAN',  (4, 0),  (6, 0)),
                ('ALIGN',  (4, 0),  (6, 0),  'CENTER'),  
                ('SPAN',  (7, 0),  (9, 0)), 
                ('ALIGN',  (7, 0),  (9, 0),  'CENTER'),
                ('ALIGN',  (1, 1),  (9, 1),  'CENTER'),
                ('BOX',(0,0),(1,-1),1,colors.blue),
                ('BOX',(1,0),(3,-1),1,colors.blue),
                ('BOX',(4,0),(6,-1),1,colors.blue),
                ('BOX',(7,0),(9,-1),1,colors.blue), 
                # Body
                ('GRID',(0,0),(-1,-1),0.5,colors.grey),
                ('ALIGN',  (0, 2),  (0, -1),  'LEFT'),
                ('ALIGN',  (1, 2),  (1, -1),  'RIGHT'),
                ('ALIGN',  (3, 2),  (3, -1),  'RIGHT'),
                ('ALIGN',  (4, 2),  (4, -1),  'RIGHT'),
                ('ALIGN',  (6, 2),  (6, -1),  'RIGHT'),
                ('ALIGN',  (7, 2),  (7, -1),  'RIGHT'),
                ('ALIGN',  (9, 2),  (9, -1),  'RIGHT'),
                #('BOX',(1,3),(3,3),3 ,colors.red),
                #('BACKGROUND',(4,3),(6,3), colors.red),
                #('BACKGROUND',(7,6),(9,6), colors.limegreen)
                #('BOX',(0,0),(-1,-1), 1,colors.black),
                #('LINEABOVE',(1,2),(-2,2),1,colors.blue),
                #('LINEBEFORE',(2,1),(2,-2),1,colors.pink),
                #('BACKGROUND', (0, 0), (0, 1), colors.pink),
                #('BACKGROUND', (1, 1), (1, 2), colors.lavender),
                #('BACKGROUND', (2, 2), (2, 3), colors.orange),
            ]
        self.defaultColWidths = [
            10 * cm,  2 * cm, 2 * cm, 2 * cm, 2 * cm, 2 * cm, 2 * cm, 2 * cm, 2 * cm, 2 * cm      
            ]
        
    def newTable(self):
        self.data = []
        self.style = []
        self.row = 0
        
    def create_pdfdoc(self,  pdfdoc):
        """
        Creates PDF doc from story.
        """
        pdf_doc = BaseDocTemplate(pdfdoc, pagesize = self.PAGE_SIZE,
            leftMargin = self.MARGIN_SIZE, rightMargin = self.MARGIN_SIZE,
            topMargin = self.MARGIN_SIZE, bottomMargin = self.MARGIN_SIZE)
        main_frame = Frame(self.MARGIN_SIZE, self.MARGIN_SIZE,
            self.PAGE_SIZE[0] - 2 * self.MARGIN_SIZE, self.PAGE_SIZE[1] - 2 * self.MARGIN_SIZE,
            leftPadding = 0, rightPadding = 0, bottomPadding = 0,
            topPadding = 0, id = 'main_frame')
        main_template = PageTemplate(id = 'main_template', frames = [main_frame])
        pdf_doc.addPageTemplates([main_template])

        pdf_doc.build(self.story)

    def setTableHeader(self,  aData = None,  aStyle = None):
        if aData == None:
            aData = self.defaultHeaderData

        for d in aData:
            self.data.append(d)
            self.row += 1
            
        if aStyle == None:
            aStyle = self.defaultHeaderStyle
            
        for s in aStyle:
            self.style.append(s)
            
    def addTableRow(self,  aData):
        self.data.append(aData)
        if 'increased' in aData[2]:
            self.style.append(('BACKGROUND',(1,self.row),(3,self.row), colors.red))
            pass
        elif 'decreased' in aData[2]:
            self.style.append(('BACKGROUND',(1,self.row),(3,self.row), colors.limegreen))
            pass
        
        if 'increased' in aData[5]:
            self.style.append(('BACKGROUND',(4,self.row),(6,self.row), colors.red))
            pass
        elif 'decreased' in aData[5]:
            self.style.append(('BACKGROUND',(4,self.row),(6,self.row), colors.limegreen))
            pass
            
        if 'increased' in aData[8]:
            self.style.append(('BACKGROUND',(7,self.row),(9,self.row), colors.red))
            pass
        elif 'decreased' in aData[8]:
            self.style.append(('BACKGROUND',(7,self.row),(9,self.row), colors.limegreen))
            pass
        
        self.row += 1
    
    def addTableToStory(self):
        t=Table(self.data, style = self.style,  colWidths = self.defaultColWidths, repeatRows = 2)
        self.story.append(t)
        
    def startNewSection(self,  title,  newPage = False):
        if newPage:
            self.story.append(PageBreak())
            
        self.story.append(Paragraph(title, self.styleSheet['Normal']))
        self.story.append(Spacer(0, 10 * mm)) 
        
    def demo(self):
        """
        Runs demo demonstrating usage of Spreadsheet Tables.
        """

        headerData= [
                ['Test case','Last two run',  '', '', 'Last five run',  '', '',  '9 runs', '' , '' ], 
                ['','Trend\nsec/run','Trend','%','Trend\nsec/run','Trend','%','Trend\nsec/run','Trend','%'],
            ]
            
        data= [
            ['01aa_createfixed32-timeactivities(false)',0.010000,'unaltered',0.313972,-0.035900,'unaltered',-1.121525,-0.118625,'unaltered',-2.697862],
            ['01aa_createfixed32-timeactivities(true)',1.437000,'increased',40.627651,0.280800,'increased',7.872161,0.001383,'unaltered',0.027957], 
            ['01ab_createunorderedappend',1.751000,'unaltered',4.099550,0.514900,'unaltered',1.227794,-2.936405,'unaltered',-3.638127], 
            ['01ac_createorderappend',0.104000,'unaltered',2.512684,-0.019800,'unaltered',-0.457698,-0.149113,'unaltered',-2.466718], 
            ['01ad_createmanycount',0.072000,'unaltered',0.340845,-0.044400,'unaltered',-0.208441,-32.269804,'decreased',-7.904151], 
            ['01ae_createswitchcount',0.033000,'unaltered',0.192780,-0.024800,'unaltered',-0.143985,-27.909875,'decreased',-7.941960], 
            ['01af_parallelmanycount',-0.011000,'unaltered',-0.191771,0.054700,'unaltered',0.944080,-0.109351,'unaltered',-1.583882], 
            ['01ag_unorderedappend2',1.013000,'unaltered',2.448043,0.039600,'unaltered',0.093981,-2.471012,'unaltered',-3.475746], 
            ['01ah_unorderedappend4',1.904000,'unaltered',3.498264,0.246100,'unaltered',0.446424,-0.827333,'unaltered',-1.269851], 
            ['1ai_unorderedappend8',0.585000,'unaltered',1.274232,0.141000,'unaltered',0.308042,-3.015595,'unaltered',-3.651770], 
            ['01aj_unorderedappend12',0.614000,'unaltered',1.381389,0.232200,'unaltered',0.530452,-3.142393,'unaltered',-3.750409], 
            ['01ak_unorderedappend16',1.190000,'unaltered',2.772213,0.542000,'unaltered',1.299013,-3.648935,'unaltered',-4.060598], 
            ['01al_unorderedappend32',0.005000,'unaltered',0.016906,-0.028900,'unaltered',-0.097797,-5.892500,'decreased',-5.806849], 
            ['01ba_writefixed32',0.033000,'unaltered',0.635838,0.025800,'unaltered',0.504596,-0.092458,'unaltered',-1.468292]
            ]
        
        headerStyle=[
         # Header
         ('SPAN',  (0, 0),  (0, 1)),
         ('VALIGN',  (0, 0),  (0, 1),  'MIDDLE'), 
         ('SPAN',  (1, 0),  (3, 0)),
         ('ALIGN',  (1, 0),  (3, 0),  'CENTER'), 
         ('SPAN',  (4, 0),  (6, 0)),
         ('ALIGN',  (4, 0),  (6, 0),  'CENTER'),  
         ('SPAN',  (7, 0),  (9, 0)), 
         ('ALIGN',  (7, 0),  (9, 0),  'CENTER'),
         ('ALIGN',  (1, 1),  (9, 1),  'CENTER'),
         ('BOX',(0,0),(1,-1),1,colors.blue),
         ('BOX',(1,0),(3,-1),1,colors.blue),
         ('BOX',(4,0),(6,-1),1,colors.blue),
         ('BOX',(7,0),(9,-1),1,colors.blue), 
         # Body
         ('GRID',(0,0),(-1,-1),0.5,colors.grey),
         #('BOX',(1,3),(3,3),3 ,colors.red),
         #('BACKGROUND',(4,3),(6,3), colors.red),
         #('BACKGROUND',(7,6),(9,6), colors.limegreen)
         #('BOX',(0,0),(-1,-1), 1,colors.black),
         #('LINEABOVE',(1,2),(-2,2),1,colors.blue),
         #('LINEBEFORE',(2,1),(2,-2),1,colors.pink),
         #('BACKGROUND', (0, 0), (0, 1), colors.pink),
         #('BACKGROUND', (1, 1), (1, 2), colors.lavender),
         #('BACKGROUND', (2, 2), (2, 3), colors.orange),
         ]
         
        self.startNewSection("Hthor results:")
        self.newTable()
        self.setTableHeader(headerData, headerStyle)
        #self.setTableHeader()
        for d in data:
            self.addTableRow(d)
            
        self.addTableToStory()
        
        self.startNewSection("Thor results:",  True)
        self.newTable()
        self.setTableHeader()
        for d in data:
            self.addTableRow(d)
        self.addTableToStory()
        
        
        self.startNewSection("Roxie results:", True)
        self.addTableToStory()
        
        self.create_pdfdoc('spreadsheet_demo2.pdf')

if __name__ == '__main__':
    
    pdfReport = PdfPerfReportGen()
    pdfReport.demo()
