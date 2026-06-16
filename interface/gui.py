import os
import sys
import psutil
from pathlib import Path

from PySide6.QtCore import Qt, QProcess, QProcessEnvironment, QTimer
from PySide6.QtGui import QFont, QTextCursor
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QRadioButton, QButtonGroup,
    QFileDialog, QTextEdit, QGroupBox, QMessageBox, QCheckBox,
    QSlider, QProgressBar
)

SCRIPT_DIR = Path(__file__).resolve().parent
APP_ROOT = SCRIPT_DIR.parent
RESULTS_DIR = APP_ROOT / "results"

MODERN_QSS = """
QWidget {
    background-color: #2b2b2b;
    color: #e0e0e0;
    font-family: 'Segoe UI', Arial, sans-serif;
    font-size: 13px;
}
QGroupBox {
    border: 1px solid #4a4a4a;
    border-radius: 6px;
    margin-top: 14px;
    padding-top: 15px;
    font-weight: bold;
}
QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    left: 10px;
    padding: 0 5px;
    color: #4da6ff;
}
QLineEdit {
    background-color: #3c3f41;
    border: 1px solid #555555;
    border-radius: 4px;
    padding: 6px;
    color: #ffffff;
}
QLineEdit:focus {
    border: 1px solid #4da6ff;
}
QPushButton {
    background-color: #4a4a4a;
    border: 1px solid #3c3f41;
    border-radius: 4px;
    padding: 6px 12px;
    color: #ffffff;
}
QPushButton:hover {
    background-color: #5a5a5a;
}
QPushButton:pressed {
    background-color: #3a3a3a;
}
QRadioButton {
    spacing: 8px;
}
QRadioButton::indicator {
    width: 16px;
    height: 16px;
}
QTextEdit {
    background-color: #1e1e1e;
    color: #d4d4d4;
    border: 1px solid #4a4a4a;
    border-radius: 4px;
    padding: 4px;
}
QProgressBar {
    border: 1px solid #4a4a4a;
    border-radius: 4px;
    text-align: center;
    background-color: #3c3f41;
}
QProgressBar::chunk {
    background-color: #4da6ff;
    width: 20px;
}
QSlider::groove:horizontal {
    border: 1px solid #4a4a4a;
    height: 8px;
    background: #3c3f41;
    border-radius: 4px;
}
QSlider::handle:horizontal {
    background: #4da6ff;
    border: 1px solid #2b2b2b;
    width: 14px;
    margin: -4px 0;
    border-radius: 7px;
}
QSlider::handle:horizontal:hover {
    background: #73c2ff;
}
"""

class NextflowGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Nextflow Germline Variant Calling")
        self.resize(1000, 850)
        
        # Hardware detection
        self.sys_cpus = psutil.cpu_count(logical=True)
        if not self.sys_cpus: self.sys_cpus = 4
        self.sys_mem_gb = int(psutil.virtual_memory().total / (1024**3))
        
        # Default to 75% for safety
        self.default_cpus = max(1, int(self.sys_cpus * 0.75))
        self.default_mem = max(2, int(self.sys_mem_gb * 0.75))

        self.setup_ui()
        self.process = None
        
        # Start hardware monitor
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_monitor)
        self.timer.start(1000) # 1 second refresh

    def setup_ui(self):
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QVBoxLayout(main_widget)
        main_layout.setSpacing(10)
        main_layout.setContentsMargins(20, 20, 20, 20)

        # ─── Pipeline Selection ───
        pipeline_group = QGroupBox("1. Select Pipeline")
        pipeline_layout = QHBoxLayout()
        self.radio_cpu = QRadioButton("CPU Pipeline (BWA, GATK)")
        self.radio_gpu = QRadioButton("GPU Pipeline (NVIDIA Parabricks)")
        self.radio_cpu.setChecked(True)
        
        self.pipeline_btn_group = QButtonGroup()
        self.pipeline_btn_group.addButton(self.radio_cpu)
        self.pipeline_btn_group.addButton(self.radio_gpu)
        
        pipeline_layout.addWidget(self.radio_cpu)
        pipeline_layout.addWidget(self.radio_gpu)
        pipeline_group.setLayout(pipeline_layout)
        main_layout.addWidget(pipeline_group)

        # ─── Configuration ───
        config_group = QGroupBox("2. Configuration")
        config_layout = QVBoxLayout()
        config_layout.setSpacing(8)

        # Cohort Name
        cohort_layout = QHBoxLayout()
        cohort_label = QLabel("Cohort Name:")
        cohort_label.setFixedWidth(150)
        cohort_layout.addWidget(cohort_label)
        self.input_cohort = QLineEdit()
        self.input_cohort.setPlaceholderText("e.g. cohort_01")
        cohort_layout.addWidget(self.input_cohort)
        config_layout.addLayout(cohort_layout)

        # Reference Name
        ref_name_layout = QHBoxLayout()
        ref_name_label = QLabel("Reference Base Name:")
        ref_name_label.setFixedWidth(150)
        ref_name_layout.addWidget(ref_name_label)
        self.input_ref_name = QLineEdit()
        self.input_ref_name.setText("hg38")
        self.input_ref_name.setPlaceholderText("e.g. hg38 (do not include .fasta)")
        ref_name_layout.addWidget(self.input_ref_name)
        config_layout.addLayout(ref_name_layout)

        # Reference Folder
        ref_dir_layout = QHBoxLayout()
        ref_dir_label = QLabel("Reference Folder:")
        ref_dir_label.setFixedWidth(150)
        ref_dir_layout.addWidget(ref_dir_label)
        self.input_ref_dir = QLineEdit()
        self.input_ref_dir.setPlaceholderText("Folder containing your reference fasta and indexes")
        self.btn_browse_ref = QPushButton("Browse...")
        self.btn_browse_ref.clicked.connect(self.browse_ref_dir)
        ref_dir_layout.addWidget(self.input_ref_dir)
        ref_dir_layout.addWidget(self.btn_browse_ref)
        config_layout.addLayout(ref_dir_layout)
        
        # Pre-built indexes checkbox
        self.check_prebuilt = QCheckBox("Pre-built BWA indexes available in Reference Folder")
        self.check_prebuilt.setChecked(True)
        self.check_prebuilt.stateChanged.connect(self.toggle_build_button)
        config_layout.addWidget(self.check_prebuilt)

        # FASTQ Folder
        fastq_dir_layout = QHBoxLayout()
        fastq_dir_label = QLabel("FASTQ Folder:")
        fastq_dir_label.setFixedWidth(150)
        fastq_dir_layout.addWidget(fastq_dir_label)
        self.input_fastq_dir = QLineEdit()
        self.input_fastq_dir.setPlaceholderText("Folder containing *_R1.fastq.gz and *_R2.fastq.gz")
        self.btn_browse_fastq = QPushButton("Browse...")
        self.btn_browse_fastq.clicked.connect(self.browse_fastq_dir)
        fastq_dir_layout.addWidget(self.input_fastq_dir)
        fastq_dir_layout.addWidget(self.btn_browse_fastq)
        config_layout.addLayout(fastq_dir_layout)

        config_group.setLayout(config_layout)
        main_layout.addWidget(config_group)

        # ─── Resource Allocation & Monitor ───
        res_group = QGroupBox("3. Resource Allocation & Live Monitor")
        res_layout = QVBoxLayout()
        res_layout.setSpacing(10)

        # Live Monitors
        monitor_layout = QHBoxLayout()
        self.cpu_bar = QProgressBar()
        self.cpu_bar.setFormat("Live CPU Usage: %p%")
        self.mem_bar = QProgressBar()
        self.mem_bar.setFormat("Live RAM Usage: %p%")
        monitor_layout.addWidget(self.cpu_bar)
        monitor_layout.addWidget(self.mem_bar)
        res_layout.addLayout(monitor_layout)

        # Sliders
        sliders_layout = QHBoxLayout()

        # CPU Slider
        cpu_box = QVBoxLayout()
        self.lbl_cpu = QLabel(f"Max CPU Cores: {self.default_cpus} / {self.sys_cpus}")
        self.lbl_cpu.setAlignment(Qt.AlignCenter)
        self.slider_cpu = QSlider(Qt.Horizontal)
        self.slider_cpu.setMinimum(1)
        self.slider_cpu.setMaximum(self.sys_cpus)
        self.slider_cpu.setValue(self.default_cpus)
        self.slider_cpu.valueChanged.connect(self.update_cpu_label)
        cpu_box.addWidget(self.lbl_cpu)
        cpu_box.addWidget(self.slider_cpu)

        # RAM Slider
        mem_box = QVBoxLayout()
        self.lbl_mem = QLabel(f"Max Memory (GB): {self.default_mem} / {self.sys_mem_gb}")
        self.lbl_mem.setAlignment(Qt.AlignCenter)
        self.slider_mem = QSlider(Qt.Horizontal)
        self.slider_mem.setMinimum(2)
        self.slider_mem.setMaximum(self.sys_mem_gb)
        self.slider_mem.setValue(self.default_mem)
        self.slider_mem.valueChanged.connect(self.update_mem_label)
        mem_box.addWidget(self.lbl_mem)
        mem_box.addWidget(self.slider_mem)

        sliders_layout.addLayout(cpu_box)
        sliders_layout.addLayout(mem_box)
        res_layout.addLayout(sliders_layout)

        res_group.setLayout(res_layout)
        main_layout.addWidget(res_group)

        # ─── Actions ───
        action_layout = QHBoxLayout()
        
        self.btn_build_index = QPushButton("Build Reference Indexes")
        self.btn_build_index.setStyleSheet("background-color: #555555; color: #888888; font-weight: bold; padding: 12px; border: none;")
        self.btn_build_index.clicked.connect(self.build_index)
        self.btn_build_index.setEnabled(False)
        
        self.btn_run_pipeline = QPushButton("Run Pipeline")
        self.btn_run_pipeline.setStyleSheet("background-color: #28a745; color: white; font-weight: bold; padding: 12px; border: none;")
        self.btn_run_pipeline.clicked.connect(self.run_pipeline)
        
        self.btn_stop = QPushButton("Stop Process")
        self.btn_stop.setStyleSheet("background-color: #dc3545; color: white; font-weight: bold; padding: 12px; border: none;")
        self.btn_stop.clicked.connect(self.stop_process)
        self.btn_stop.setEnabled(False)

        action_layout.addWidget(self.btn_build_index)
        action_layout.addWidget(self.btn_run_pipeline)
        action_layout.addWidget(self.btn_stop)
        main_layout.addLayout(action_layout)

        # ─── Console Output ───
        console_group = QGroupBox("Console Output")
        console_layout = QVBoxLayout()
        console_layout.setContentsMargins(0, 10, 0, 0)
        self.console = QTextEdit()
        self.console.setReadOnly(True)
        self.console.setFont(QFont("Consolas", 10))
        console_layout.addWidget(self.console)
        console_group.setLayout(console_layout)
        main_layout.addWidget(console_group)
        
        # Initial psutil call to clear baseline
        psutil.cpu_percent()

    def update_monitor(self):
        cpu = psutil.cpu_percent()
        mem = psutil.virtual_memory().percent
        self.cpu_bar.setValue(int(cpu))
        self.mem_bar.setValue(int(mem))
        
        # Change color based on load
        cpu_color = "#dc3545" if cpu > 85 else ("#d39e00" if cpu > 60 else "#28a745")
        mem_color = "#dc3545" if mem > 85 else ("#d39e00" if mem > 60 else "#28a745")
        
        self.cpu_bar.setStyleSheet(f"""
            QProgressBar {{ border: 1px solid #4a4a4a; border-radius: 4px; text-align: center; background-color: #3c3f41; }}
            QProgressBar::chunk {{ background-color: {cpu_color}; width: 20px; }}
        """)
        self.mem_bar.setStyleSheet(f"""
            QProgressBar {{ border: 1px solid #4a4a4a; border-radius: 4px; text-align: center; background-color: #3c3f41; }}
            QProgressBar::chunk {{ background-color: {mem_color}; width: 20px; }}
        """)

    def update_cpu_label(self, val):
        self.lbl_cpu.setText(f"Max CPU Cores: {val} / {self.sys_cpus}")

    def update_mem_label(self, val):
        self.lbl_mem.setText(f"Max Memory (GB): {val} / {self.sys_mem_gb}")

    def toggle_build_button(self, state):
        if state == 2:
            self.btn_build_index.setEnabled(False)
            self.btn_build_index.setStyleSheet("background-color: #555555; color: #888888; font-weight: bold; padding: 12px; border: none;")
        else:
            self.btn_build_index.setEnabled(True)
            self.btn_build_index.setStyleSheet("background-color: #d39e00; color: white; font-weight: bold; padding: 12px; border: none;")

    def browse_ref_dir(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Reference Folder")
        if folder:
            self.input_ref_dir.setText(os.path.normpath(folder))

    def browse_fastq_dir(self):
        folder = QFileDialog.getExistingDirectory(self, "Select FASTQ Folder")
        if folder:
            self.input_fastq_dir.setText(os.path.normpath(folder))

    def append_console(self, text):
        self.console.moveCursor(QTextCursor.End)
        self.console.insertPlainText(text)
        self.console.moveCursor(QTextCursor.End)

    def to_linux_path(self, path_str):
        path = path_str.replace('\\', '/')
        if len(path) > 1 and path[1] == ':':
            drive = path[0].lower()
            path = f"/mnt/{drive}{path[2:]}"
        return path

    def validate_inputs(self, check_fastq=True):
        if not self.input_ref_name.text().strip():
            QMessageBox.warning(self, "Validation Error", "Reference Base Name cannot be empty.")
            return False
        if not self.input_ref_dir.text().strip():
            QMessageBox.warning(self, "Validation Error", "Reference Folder cannot be empty.")
            return False
        if check_fastq:
            if not self.input_cohort.text().strip():
                QMessageBox.warning(self, "Validation Error", "Cohort Name cannot be empty.")
                return False
            if not self.input_fastq_dir.text().strip():
                QMessageBox.warning(self, "Validation Error", "FASTQ Folder cannot be empty.")
                return False
        return True

    def start_process(self, command, env_dict=None):
        if self.process and self.process.state() == QProcess.Running:
            QMessageBox.warning(self, "Warning", "A process is already running!")
            return

        self.console.clear()
        self.append_console(f"Running command: {' '.join(command)}\n")
        self.append_console("-" * 60 + "\n")

        self.process = QProcess()
        
        env = QProcessEnvironment.systemEnvironment()
        if env_dict:
            for k, v in env_dict.items():
                env.insert(k, v)
        self.process.setProcessEnvironment(env)
        
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.process_finished)

        self.btn_run_pipeline.setEnabled(False)
        self.btn_build_index.setEnabled(False)
        self.btn_stop.setEnabled(True)

        self.process.start(command[0], command[1:])

    def handle_stdout(self):
        data = self.process.readAllStandardOutput()
        text = bytes(data).decode("utf-8", errors="replace")
        self.append_console(text)

    def handle_stderr(self):
        data = self.process.readAllStandardError()
        text = bytes(data).decode("utf-8", errors="replace")
        self.append_console(text)

    def process_finished(self, exit_code, exit_status):
        self.append_console("-" * 60 + "\n")
        self.append_console(f"Process finished with exit code {exit_code}\n")
        self.btn_run_pipeline.setEnabled(True)
        self.toggle_build_button(self.check_prebuilt.checkState().value)
        self.btn_stop.setEnabled(False)

    def stop_process(self):
        if self.process and self.process.state() == QProcess.Running:
            self.append_console("\nStopping process...\n")
            self.process.kill()

    def build_index(self):
        if not self.validate_inputs(check_fastq=False):
            return

        ref_dir = self.input_ref_dir.text().strip()
        ref_name = self.input_ref_name.text().strip()
        
        ref_dir_linux = self.to_linux_path(ref_dir)

        script_path = APP_ROOT / "pipelines" / "germline_cpu" / "Germline_CPU_reference_builder.sh"
        script_path_str = str(script_path).replace("\\", "/")

        cmd = ["bash", script_path_str, ref_dir_linux, ref_name]
        self.start_process(cmd)

    def run_pipeline(self):
        if not self.validate_inputs(check_fastq=True):
            return

        cohort = self.input_cohort.text().strip()
        ref_dir = self.input_ref_dir.text().strip()
        ref_name = self.input_ref_name.text().strip()
        fastq_dir = self.input_fastq_dir.text().strip()

        ref_dir_linux = self.to_linux_path(ref_dir)
        fastq_dir_linux = self.to_linux_path(fastq_dir)
        results_dir_linux = self.to_linux_path(str(RESULTS_DIR))

        env_dict = {
            "REF_DIR": ref_dir_linux,
            "REF_NAME": ref_name,
            "RESULTS_DIR": results_dir_linux,
            "SKIP_INDEXING": "1" if self.check_prebuilt.isChecked() else "0",
            "MAX_CPUS": str(self.slider_cpu.value()),
            "MAX_MEM_GB": str(self.slider_mem.value())
        }

        if self.radio_cpu.isChecked():
            script_path = APP_ROOT / "pipelines" / "germline_cpu" / "Germline_CPU_run.sh"
        else:
            script_path = APP_ROOT / "pipelines" / "germline_gpu" / "Germline_pipeline_run.sh"

        script_path_str = str(script_path).replace("\\", "/")
        cmd = ["bash", script_path_str, cohort, fastq_dir_linux]
        
        self.start_process(cmd, env_dict)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setStyleSheet(MODERN_QSS)
    window = NextflowGUI()
    window.show()
    sys.exit(app.exec())
