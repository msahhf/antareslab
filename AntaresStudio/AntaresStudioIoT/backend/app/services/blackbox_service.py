"""
AntaresStudio IoT - Black Box (Kara Kutu) Service v3.2

Generates professional PDF mission reports from black box telemetry data.
Uses fpdf2 for modern PDF generation with tables and charts.
"""

import logging
import csv
import io
import statistics
from datetime import datetime
from pathlib import Path
from dataclasses import dataclass
from typing import List, Dict, Optional, Tuple

from fpdf import FPDF

from app.config import settings

logger = logging.getLogger("antares.blackbox")


@dataclass
class TelemetryReading:
    """Single telemetry reading from black box."""
    timestamp: int
    datetime_str: str
    temperature: float
    humidity: int
    soil_moisture: int
    heater_power: int
    fan_sly: bool
    fan_dz: bool
    mode: str


@dataclass
class MissionStatistics:
    """Computed statistics for the mission."""
    duration_seconds: int
    reading_count: int
    avg_temperature: float
    min_temperature: float
    max_temperature: float
    avg_humidity: float
    min_humidity: int
    max_humidity: int
    avg_soil_moisture: float
    heater_on_percent: float
    fan_sly_on_percent: float
    fan_dz_on_percent: float
    mode_changes: int


class MissionPDF(FPDF):
    """Custom PDF class for mission reports."""
    
    def __init__(self):
        super().__init__(orientation='P', unit='mm', format='A4')
        self.set_auto_page_break(auto=True, margin=15)
        self.set_margins(left=15, top=15, right=15)
    
    def header(self):
        """Add header to each page."""
        # Logo/Title area
        self.set_font('Arial', 'B', 16)
        self.set_text_color(33, 37, 41)  # Dark gray
        
        # Team Quareka branding
        self.cell(0, 10, 'TEAM QUAREKA', ln=True, align='L')
        
        self.set_font('Arial', '', 12)
        self.set_text_color(108, 117, 125)  # Medium gray
        self.cell(0, 6, 'Antares Archaeology Capsule', ln=True, align='L')
        
        # Decorative line
        self.set_draw_color(0, 123, 255)  # Blue
        self.set_line_width(0.5)
        self.line(15, 35, 195, 35)
        
        # Report title
        self.set_y(40)
        self.set_font('Arial', 'B', 14)
        self.set_text_color(0, 123, 255)
        self.cell(0, 10, 'MISSION REPORT', ln=True, align='C')
        
        self.ln(5)
    
    def footer(self):
        """Add footer to each page."""
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.set_text_color(128, 128, 128)
        self.cell(0, 10, f'Page {self.page_no()}', align='C')
    
    def chapter_title(self, title: str):
        """Add section title."""
        self.set_font('Arial', 'B', 12)
        self.set_text_color(33, 37, 41)
        self.set_fill_color(240, 240, 240)
        self.cell(0, 8, title, ln=True, fill=True)
        self.ln(2)
    
    def stat_box(self, label: str, value: str, x: float, y: float, width: float = 45):
        """Draw a statistics box."""
        self.set_xy(x, y)
        
        # Box background
        self.set_fill_color(248, 249, 250)
        self.set_draw_color(222, 226, 230)
        self.rect(x, y, width, 18, style='DF')
        
        # Label
        self.set_font('Arial', '', 8)
        self.set_text_color(108, 117, 125)
        self.set_xy(x + 2, y + 2)
        self.cell(width - 4, 5, label)
        
        # Value
        self.set_font('Arial', 'B', 11)
        self.set_text_color(33, 37, 41)
        self.set_xy(x + 2, y + 8)
        self.cell(width - 4, 8, value)
    
    def data_table(self, readings: List[TelemetryReading], limit: int = 50):
        """Add data table with telemetry readings."""
        # Show limited rows with note
        display_readings = readings[:limit]
        
        # Table header
        self.set_font('Arial', 'B', 8)
        self.set_fill_color(0, 123, 255)
        self.set_text_color(255, 255, 255)
        
        col_widths = [20, 20, 25, 20, 25, 15, 15, 15, 20]
        headers = ['Time', 'Temp', 'Humidity', 'Soil', 'Heater', 'F.SLY', 'F.DZ', 'Mode']
        
        for i, header in enumerate(headers):
            self.cell(col_widths[i], 7, header, border=1, fill=True, align='C')
        self.ln()
        
        # Table rows
        self.set_font('Arial', '', 7)
        self.set_text_color(33, 37, 41)
        self.set_fill_color(255, 255, 255)
        
        for reading in display_readings:
            row_fill = len(self.readings) % 2 == 0  # Alternating colors
            if row_fill:
                self.set_fill_color(248, 249, 250)
            else:
                self.set_fill_color(255, 255, 255)
            
            self.cell(col_widths[0], 6, reading.datetime_str[:8], border=1, align='C', fill=True)
            self.cell(col_widths[1], 6, f'{reading.temperature:.1f}°C', border=1, align='C', fill=True)
            self.cell(col_widths[2], 6, f'{reading.humidity}%', border=1, align='C', fill=True)
            self.cell(col_widths[3], 6, str(reading.soil_moisture), border=1, align='C', fill=True)
            self.cell(col_widths[4], 6, f'{reading.heater_power}%', border=1, align='C', fill=True)
            self.cell(col_widths[5], 6, 'ON' if reading.fan_sly else 'OFF', border=1, align='C', fill=True)
            self.cell(col_widths[6], 6, 'ON' if reading.fan_dz else 'OFF', border=1, align='C', fill=True)
            self.cell(col_widths[7], 6, reading.mode[:8], border=1, align='C', fill=True)
            self.ln()
        
        # Note about truncated data
        if len(readings) > limit:
            self.ln(3)
            self.set_font('Arial', 'I', 8)
            self.set_text_color(108, 117, 125)
            self.cell(0, 5, f'... and {len(readings) - limit} more readings (see raw data file)', ln=True)


class BlackBoxService:
    """Service for processing black box data and generating reports."""
    
    def __init__(self):
        self.reports_dir = settings.BASE_DIR / "data" / "reports"
        self.reports_dir.mkdir(parents=True, exist_ok=True)
    
    def parse_blackbox_data(self, content: str) -> List[TelemetryReading]:
        """
        Parse black box CSV content into readings.
        
        Expected format:
        timestamp,datetime,temperature,humidity,soil_moisture,heater_power,fan_sly,fan_dz,mode
        """
        readings = []
        
        try:
            reader = csv.reader(io.StringIO(content))
            
            # Skip header
            next(reader, None)
            
            for row in reader:
                if len(row) < 9:
                    continue
                
                # Skip mission markers
                if row[0].startswith('MISSION'):
                    continue
                
                try:
                    reading = TelemetryReading(
                        timestamp=int(row[0]),
                        datetime_str=row[1],
                        temperature=float(row[2]),
                        humidity=int(row[3]),
                        soil_moisture=int(row[4]),
                        heater_power=int(row[5]),
                        fan_sly=row[6].upper() in ['ON', 'TRUE', '1'],
                        fan_dz=row[7].upper() in ['ON', 'TRUE', '1'],
                        mode=row[8]
                    )
                    readings.append(reading)
                except (ValueError, IndexError) as e:
                    logger.warning(f"Skipping malformed row: {row} - {e}")
                    continue
        
        except Exception as e:
            logger.error(f"Error parsing black box data: {e}")
        
        return readings
    
    def compute_statistics(self, readings: List[TelemetryReading]) -> MissionStatistics:
        """Compute mission statistics from readings."""
        if not readings:
            return MissionStatistics(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        
        temps = [r.temperature for r in readings]
        humidities = [r.humidity for r in readings]
        soils = [r.soil_moisture for r in readings]
        
        # Time calculations
        start_time = readings[0].timestamp
        end_time = readings[-1].timestamp
        duration = end_time - start_time
        
        # Count mode changes
        mode_changes = 0
        prev_mode = readings[0].mode
        for r in readings[1:]:
            if r.mode != prev_mode:
                mode_changes += 1
                prev_mode = r.mode
        
        # Calculate fan on percentages
        sly_on = sum(1 for r in readings if r.fan_sly)
        dz_on = sum(1 for r in readings if r.fan_dz)
        heater_total = sum(r.heater_power for r in readings)
        
        return MissionStatistics(
            duration_seconds=duration // 1000,  # Convert from ms to s
            reading_count=len(readings),
            avg_temperature=statistics.mean(temps),
            min_temperature=min(temps),
            max_temperature=max(temps),
            avg_humidity=statistics.mean(humidities),
            min_humidity=min(humidities),
            max_humidity=max(humidities),
            avg_soil_moisture=statistics.mean(soils),
            heater_on_percent=(heater_total / (len(readings) * 100)) * 100,
            fan_sly_on_percent=(sly_on / len(readings)) * 100,
            fan_dz_on_percent=(dz_on / len(readings)) * 100,
            mode_changes=mode_changes
        )
    
    def generate_pdf_report(
        self,
        readings: List[TelemetryReading],
        mission_name: str = "Capsule Mission"
    ) -> Tuple[Path, str]:
        """
        Generate professional PDF mission report.
        
        Returns:
            Tuple of (pdf_path, pdf_filename)
        """
        stats = self.compute_statistics(readings)
        
        # Generate filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"Mission_Report_{timestamp}.pdf"
        pdf_path = self.reports_dir / filename
        
        # Create PDF
        pdf = MissionPDF()
        pdf.add_page()
        pdf.readings = readings  # Store for table method
        
        # Mission info section
        pdf.chapter_title('Mission Information')
        
        pdf.set_font('Arial', '', 10)
        pdf.set_text_color(33, 37, 41)
        pdf.cell(40, 7, 'Mission Name:', ln=0)
        pdf.cell(0, 7, mission_name, ln=True)
        pdf.cell(40, 7, 'Generated:', ln=0)
        pdf.cell(0, 7, datetime.now().strftime("%Y-%m-%d %H:%M:%S"), ln=True)
        pdf.cell(40, 7, 'Duration:', ln=0)
        
        duration_str = self._format_duration(stats.duration_seconds)
        pdf.cell(0, 7, duration_str, ln=True)
        pdf.cell(40, 7, 'Data Points:', ln=0)
        pdf.cell(0, 7, str(stats.reading_count), ln=True)
        
        pdf.ln(5)
        
        # Statistics boxes
        pdf.chapter_title('Summary Statistics')
        
        y_pos = pdf.get_y()
        pdf.stat_box('Avg Temperature', f'{stats.avg_temperature:.1f}°C', 15, y_pos)
        pdf.stat_box('Temperature Range', f'{stats.min_temperature:.1f} - {stats.max_temperature:.1f}°C', 65, y_pos)
        pdf.stat_box('Avg Humidity', f'{stats.avg_humidity:.0f}%', 115, y_pos)
        pdf.stat_box('Humidity Range', f'{stats.min_humidity} - {stats.max_humidity}%', 165, y_pos)
        
        y_pos += 22
        pdf.stat_box('Avg Soil Moist.', f'{stats.avg_soil_moisture:.0f}', 15, y_pos)
        pdf.stat_box('Heater Usage', f'{stats.heater_on_percent:.0f}%', 65, y_pos)
        pdf.stat_box('Fan SLY On', f'{stats.fan_sly_on_percent:.0f}%', 115, y_pos)
        pdf.stat_box('Fan DZ On', f'{stats.fan_dz_on_percent:.0f}%', 165, y_pos)
        
        pdf.set_y(y_pos + 25)
        
        # Data table
        pdf.chapter_title('Telemetry Data Log')
        pdf.data_table(readings, limit=40)
        
        # Footer note
        pdf.ln(10)
        pdf.set_font('Arial', 'I', 8)
        pdf.set_text_color(108, 117, 125)
        pdf.multi_cell(0, 5, 
            'This report was automatically generated by the Antares Archaeology Capsule system. '
            'Data recorded during the mission has been verified and stored in the system database. '
            'For questions, contact Team Quareka.'
        )
        
        # Save PDF
        pdf.output(str(pdf_path))
        
        logger.info(f"Generated mission report: {pdf_path} ({stats.reading_count} readings)")
        
        return pdf_path, filename
    
    def _format_duration(self, seconds: int) -> str:
        """Format seconds as human-readable duration."""
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        
        if hours > 0:
            return f"{hours}h {minutes}m {secs}s"
        elif minutes > 0:
            return f"{minutes}m {secs}s"
        else:
            return f"{secs}s"
    
    def save_raw_data(self, content: str, filename: str = None) -> Path:
        """Save raw black box data file for reference."""
        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"blackbox_raw_{timestamp}.txt"
        
        raw_path = self.reports_dir / filename
        raw_path.write_text(content, encoding='utf-8')
        
        return raw_path


# Singleton instance
blackbox_service = BlackBoxService()
