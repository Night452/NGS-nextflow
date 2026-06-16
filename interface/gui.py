import os
import sys
import psutil
from pathlib import Path

from PySide6.QtCore import Qt, QProcess, QProcessEnvironment, QTimer
from PySide6.QtGui import QFont, QTextCursor
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QFileDialog, QTextEdit, QGroupBox, 
    QMessageBox, QCheckBox, QSlider, QProgressBar, QTabWidget, QDialog
)

SCRIPT_DIR = Path(__file__).resolve().parent
APP_ROOT = SCRIPT_DIR.parent
RESULTS_DIR = APP_ROOT / "results"

MODERN_QSS = """
QWidget {
    background-color: #1e1e1e;
    color: #e0e0e0;
    font-family: 'Segoe UI', Arial, sans-serif;
    font-size: 13px;
}
QTabWidget::pane {
    border: 1px solid #333333;
    border-radius: 8px;
    background: #252526;
}
QTabBar::tab {
    background: #2d2d2d;
    color: #9d9d9d;
    padding: 10px 20px;
    border-top-left-radius: 8px;
    border-top-right-radius: 8px;
    margin-right: 2px;
}
QTabBar::tab:selected {
    background: #252526;
    color: #ffffff;
    font-weight: bold;
    border: 1px solid #333333;
    border-bottom: none;
}
QTabBar::tab:hover:!selected {
    background: #3a3a3a;
}
QGroupBox {
    border: 1px solid #333333;
    border-radius: 8px;
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
    background-color: #2d2d2d;
    border: 1px solid #3c3c3c;
    border-radius: 6px;
    padding: 8px;
    color: #ffffff;
}
QLineEdit:focus {
    border: 1px solid #4da6ff;
}
QPushButton {
    background-color: #333333;
    border: 1px solid #444444;
    border-radius: 6px;
    padding: 8px 16px;
    color: #ffffff;
    font-weight: bold;
}
QPushButton:hover {
    background-color: #4a4a4a;
    border: 1px solid #666666;
}
QPushButton:pressed {
    background-color: #2a2a2a;
}
QPushButton:disabled {
    background: #222222;
    color: #666666;
}
QCheckBox {
    background-color: #2a2a2a;
    border: 1px solid #444444;
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 14px;
    font-weight: bold;
    color: #ffffff;
}
QCheckBox::indicator {
    width: 18px;
    height: 18px;
}
QTextEdit {
    background-color: #121212;
    color: #d4d4d4;
    border: 1px solid #333333;
    border-radius: 8px;
    padding: 8px;
}
QProgressBar {
    border: 1px solid #333333;
    border-radius: 6px;
    text-align: center;
    background-color: #2d2d2d;
}
QProgressBar::chunk {
    background-color: #4da6ff;
    border-radius: 5px;
}
QSlider::groove:horizontal {
    border: 1px solid #333333;
    height: 8px;
    background: #2d2d2d;
    border-radius: 4px;
}
QSlider::handle:horizontal {
    background: #4da6ff;
    border: 1px solid #1e1e1e;
    width: 16px;
    margin: -4px 0;
    border-radius: 8px;
}
QSlider::handle:horizontal:hover {
    background: #73c2ff;
}
"""

class ResourceMonitor(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Resource Monitor & Allocation")
        self.resize(500, 300)
        self.setWindowFlags(self.windowFlags() | Qt.Tool)
        
        self.sys_cpus = psutil.cpu_count(logical=True) or 4
        self.sys_mem_gb = int(psutil.virtual_memory().total / (1024**3))
        
        self.parent_gui = parent
        self.setup_ui()
        
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.update_monitor)
        self.timer.start(1000)

    def setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)
        
        monitor_group = QGroupBox("Live Hardware Usage")
        m_layout = QVBoxLayout()
        self.cpu_bar = QProgressBar()
        self.cpu_bar.setFormat("CPU Usage: %p%")
        self.mem_bar = QProgressBar()
        self.mem_bar.setFormat("RAM Usage: %p%")
        m_layout.addWidget(self.cpu_bar)
        m_layout.addWidget(self.mem_bar)
        monitor_group.setLayout(m_layout)
        layout.addWidget(monitor_group)

        alloc_group = QGroupBox("Pipeline Resource Allocation")
        a_layout = QVBoxLayout()
        
        self.lbl_cpu = QLabel(f"Max CPU Cores: {self.parent_gui.alloc_cpus} / {self.sys_cpus}")
        self.slider_cpu = QSlider(Qt.Horizontal)
        self.slider_cpu.setMinimum(1)
        self.slider_cpu.setMaximum(self.sys_cpus)
        self.slider_cpu.setValue(self.parent_gui.alloc_cpus)
        self.slider_cpu.valueChanged.connect(self.update_cpu)
        a_layout.addWidget(self.lbl_cpu)
        a_layout.addWidget(self.slider_cpu)
        
        self.lbl_mem = QLabel(f"Max Memory (GB): {self.parent_gui.alloc_mem} / {self.sys_mem_gb}")
        self.slider_mem = QSlider(Qt.Horizontal)
        self.slider_mem.setMinimum(2)
        self.slider_mem.setMaximum(self.sys_mem_gb)
        self.slider_mem.setValue(self.parent_gui.alloc_mem)
        self.slider_mem.valueChanged.connect(self.update_mem)
        a_layout.addWidget(self.lbl_mem)
        a_layout.addWidget(self.slider_mem)
        
        alloc_group.setLayout(a_layout)
        layout.addWidget(alloc_group)

        btn_close = QPushButton("Close")
        btn_close.clicked.connect(self.accept)
        layout.addWidget(btn_close, alignment=Qt.AlignRight)

    def update_cpu(self, val):
        self.parent_gui.alloc_cpus = val
        self.lbl_cpu.setText(f"Max CPU Cores: {val} / {self.sys_cpus}")

    def update_mem(self, val):
        self.parent_gui.alloc_mem = val
        self.lbl_mem.setText(f"Max Memory (GB): {val} / {self.sys_mem_gb}")

    def update_monitor(self):
        cpu = psutil.cpu_percent()
        mem = psutil.virtual_memory().percent
        self.cpu_bar.setValue(int(cpu))
        self.mem_bar.setValue(int(mem))
        
        cpu_color = "#dc3545" if cpu > 85 else ("#d39e00" if cpu > 60 else "#28a745")
        mem_color = "#dc3545" if mem > 85 else ("#d39e00" if mem > 60 else "#28a745")
        
        self.cpu_bar.setStyleSheet(f"QProgressBar::chunk {{ background-color: {cpu_color}; border-radius: 5px; }}")
        self.mem_bar.setStyleSheet(f"QProgressBar::chunk {{ background-color: {mem_color}; border-radius: 5px; }}")

class PipelineTab(QWidget):
    def __init__(self, pipeline_type, parent=None):
        super().__init__(parent)
        self.pipeline_type = pipeline_type
        self.parent_gui = parent
        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        input_group = QGroupBox("Configuration")
        i_layout = QVBoxLayout()
        i_layout.setSpacing(10)

        name_layout = QHBoxLayout()
        name_label = QLabel("Project Name:" if "ChIP" in self.pipeline_type else "Cohort Name:")
        name_label.setFixedWidth(150)
        self.input_name = QLineEdit()
        self.input_name.setPlaceholderText("e.g. project_01")
        name_layout.addWidget(name_label)
        name_layout.addWidget(self.input_name)
        i_layout.addLayout(name_layout)

        ref_name_layout = QHBoxLayout()
        ref_name_label = QLabel("Reference Base Name:")
        ref_name_label.setFixedWidth(150)
        self.input_ref_name = QLineEdit("hg38")
        self.input_ref_name.setPlaceholderText("e.g. hg38 (no .fasta)")
        ref_name_layout.addWidget(ref_name_label)
        ref_name_layout.addWidget(self.input_ref_name)
        i_layout.addLayout(ref_name_layout)

        ref_dir_layout = QHBoxLayout()
        ref_dir_label = QLabel("Reference Folder:")
        ref_dir_label.setFixedWidth(150)
        self.input_ref_dir = QLineEdit()
        self.input_ref_dir.setPlaceholderText("Folder with reference fasta and indexes")
        self.btn_browse_ref = QPushButton("Browse...")
        self.btn_browse_ref.clicked.connect(self.browse_ref)
        ref_dir_layout.addWidget(ref_dir_label)
        ref_dir_layout.addWidget(self.input_ref_dir)
        ref_dir_layout.addWidget(self.btn_browse_ref)
        i_layout.addLayout(ref_dir_layout)

        if "Germline" in self.pipeline_type:
            self.check_prebuilt = QCheckBox("Pre-built BWA indexes available in Reference Folder")
            self.check_prebuilt.setChecked(True)
            self.check_prebuilt.stateChanged.connect(self.toggle_build_btn)
            i_layout.addWidget(self.check_prebuilt)

        fastq_dir_layout = QHBoxLayout()
        fastq_dir_label = QLabel("FASTQ Folder:")
        fastq_dir_label.setFixedWidth(150)
        self.input_fastq_dir = QLineEdit()
        self.input_fastq_dir.setPlaceholderText("Folder with *_R1.fastq.gz and *_R2.fastq.gz")
        self.btn_browse_fastq = QPushButton("Browse...")
        self.btn_browse_fastq.clicked.connect(self.browse_fastq)
        fastq_dir_layout.addWidget(fastq_dir_label)
        fastq_dir_layout.addWidget(self.input_fastq_dir)
        fastq_dir_layout.addWidget(self.btn_browse_fastq)
        i_layout.addLayout(fastq_dir_layout)

        if "ChIP" in self.pipeline_type:
            sample_layout = QHBoxLayout()
            sample_label = QLabel("Samplesheet (Optional):")
            sample_label.setFixedWidth(150)
            self.input_sample = QLineEdit()
            self.input_sample.setPlaceholderText("Path to samplesheet.csv (for controls)")
            self.btn_browse_sample = QPushButton("Browse...")
            self.btn_browse_sample.clicked.connect(self.browse_sample)
            sample_layout.addWidget(sample_label)
            sample_layout.addWidget(self.input_sample)
            sample_layout.addWidget(self.btn_browse_sample)
            i_layout.addLayout(sample_layout)

        if "GPU" in self.pipeline_type:
            self.check_low_mem = QCheckBox("Low Memory Mode (<12GB VRAM)")
            self.check_low_mem.setChecked(False)
            i_layout.addWidget(self.check_low_mem)

        input_group.setLayout(i_layout)
        layout.addWidget(input_group)

        action_layout = QHBoxLayout()
        
        if "Germline" in self.pipeline_type:
            self.btn_build = QPushButton("Build Reference Indexes")
            self.btn_build.setStyleSheet("background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #ffb703, stop:1 #fb8500); color: white; font-weight: bold; padding: 10px; border-radius: 6px; border: none;")
            self.btn_build.setEnabled(False)
            self.btn_build.clicked.connect(self.build_indexes)
            action_layout.addWidget(self.btn_build)

        self.btn_run = QPushButton("Run Pipeline")
        self.btn_run.setStyleSheet("background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #00b4d8, stop:1 #0077b6); color: white; font-weight: bold; padding: 10px; border-radius: 6px; border: none;")
        self.btn_run.clicked.connect(self.run_pipeline)
        action_layout.addWidget(self.btn_run)

        self.btn_stop = QPushButton("Stop")
        self.btn_stop.setStyleSheet("background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #ff4d6d, stop:1 #c9184a); color: white; font-weight: bold; padding: 10px; border-radius: 6px; border: none;")
        self.btn_stop.setEnabled(False)
        self.btn_stop.clicked.connect(self.parent_gui.stop_process)
        action_layout.addWidget(self.btn_stop)

        layout.addLayout(action_layout)
        layout.addStretch()

    def browse_ref(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Reference Folder")
        if folder: self.input_ref_dir.setText(os.path.normpath(folder))

    def browse_fastq(self):
        folder = QFileDialog.getExistingDirectory(self, "Select FASTQ Folder")
        if folder: self.input_fastq_dir.setText(os.path.normpath(folder))

    def browse_sample(self):
        file, _ = QFileDialog.getOpenFileName(self, "Select Samplesheet", "", "CSV Files (*.csv)")
        if file: self.input_sample.setText(os.path.normpath(file))

    def toggle_build_btn(self, state):
        if hasattr(self, 'btn_build'):
            if state == 2:
                self.btn_build.setEnabled(False)
                self.btn_build.setStyleSheet("background: #2a2a2a; color: #666666; border: none;")
            else:
                self.btn_build.setEnabled(True)
                self.btn_build.setStyleSheet("background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #ffb703, stop:1 #fb8500); color: white; font-weight: bold; padding: 10px; border-radius: 6px; border: none;")

    def build_indexes(self):
        if not self.input_ref_name.text() or not self.input_ref_dir.text():
            QMessageBox.warning(self, "Error", "Reference Name and Folder are required.")
            return

        ref_dir = self.parent_gui.to_linux_path(self.input_ref_dir.text().strip())
        ref_name = self.input_ref_name.text().strip()
        script = APP_ROOT / "pipelines" / "germline_cpu" / "Germline_CPU_reference_builder.sh"
        
        self.parent_gui.start_process(["bash", str(script).replace("\\", "/"), ref_dir, ref_name], self.btn_run, self.btn_stop, self.btn_build)

    def run_pipeline(self):
        if not all([self.input_name.text(), self.input_ref_name.text(), self.input_ref_dir.text(), self.input_fastq_dir.text()]):
            QMessageBox.warning(self, "Error", "Name, Reference, and FASTQ fields are required.")
            return

        name = self.input_name.text().strip()
        ref_dir = self.parent_gui.to_linux_path(self.input_ref_dir.text().strip())
        ref_name = self.input_ref_name.text().strip()
        fastq_dir = self.parent_gui.to_linux_path(self.input_fastq_dir.text().strip())
        res_dir = self.parent_gui.to_linux_path(self.parent_gui.input_out_dir.text().strip())

        env = {
            "REF_DIR": ref_dir,
            "REF_NAME": ref_name,
            "RESULTS_DIR": res_dir,
            "MAX_CPUS": str(self.parent_gui.alloc_cpus),
            "MAX_MEM_GB": str(self.parent_gui.alloc_mem)
        }

        if "Germline" in self.pipeline_type:
            env["SKIP_INDEXING"] = "1" if self.check_prebuilt.isChecked() else "0"
            
        if "GPU" in self.pipeline_type:
            if self.check_low_mem.isChecked():
                env["LOW_MEMORY"] = "1"

        if self.pipeline_type == "Germline CPU":
            script = APP_ROOT / "pipelines" / "germline_cpu" / "Germline_CPU_run.sh"
            cmd = ["bash", str(script).replace("\\", "/"), name, fastq_dir]
        elif self.pipeline_type == "Germline GPU":
            script = APP_ROOT / "pipelines" / "germline_gpu" / "Germline_pipeline_run.sh"
            cmd = ["bash", str(script).replace("\\", "/"), name, fastq_dir]
        elif self.pipeline_type == "ChIP-seq GPU":
            script = APP_ROOT / "pipelines" / "chipseq" / "CHIPseq_GPU_run.sh"
            sample = self.parent_gui.to_linux_path(self.input_sample.text().strip()) if self.input_sample.text().strip() else ""
            cmd = ["bash", str(script).replace("\\", "/"), name, fastq_dir, sample]

        btn_bld = self.btn_build if hasattr(self, 'btn_build') else None
        self.parent_gui.start_process(cmd, self.btn_run, self.btn_stop, btn_bld, env)


class NextflowGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Nextflow Genomics GUI")
        self.resize(1000, 800)
        
        sys_cpus = psutil.cpu_count(logical=True) or 4
        sys_mem = int(psutil.virtual_memory().total / (1024**3))
        self.alloc_cpus = max(1, int(sys_cpus * 0.75))
        self.alloc_mem = max(2, int(sys_mem * 0.75))

        self.process = None
        self.active_run_btn = None
        self.active_stop_btn = None
        self.active_build_btn = None

        self.setup_ui()

    def setup_ui(self):
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QVBoxLayout(main_widget)
        main_layout.setContentsMargins(20, 20, 20, 20)
        main_layout.setSpacing(15)

        top_bar = QHBoxLayout()
        title = QLabel("Genomics Pipeline Manager")
        title.setStyleSheet("font-size: 18px; font-weight: bold; color: #4da6ff;")
        
        btn_monitor = QPushButton("📊 Resource Monitor")
        btn_monitor.setStyleSheet("background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #f72585, stop:1 #7209b7); color: white; font-weight: bold; padding: 10px 20px; border-radius: 8px; border: none;")
        btn_monitor.clicked.connect(self.show_monitor)
        
        top_bar.addWidget(title)
        top_bar.addStretch()
        top_bar.addWidget(btn_monitor)
        main_layout.addLayout(top_bar)

        out_group = QGroupBox("Global Output Directory")
        out_layout = QHBoxLayout()
        out_label = QLabel("Save Results To:")
        out_label.setFixedWidth(120)
        self.input_out_dir = QLineEdit(str(RESULTS_DIR))
        self.btn_browse_out = QPushButton("Browse...")
        self.btn_browse_out.clicked.connect(self.browse_out)
        out_layout.addWidget(out_label)
        out_layout.addWidget(self.input_out_dir)
        out_layout.addWidget(self.btn_browse_out)
        out_group.setLayout(out_layout)
        main_layout.addWidget(out_group)

        self.tabs = QTabWidget()
        self.tab_germline_cpu = PipelineTab("Germline CPU", self)
        self.tab_germline_gpu = PipelineTab("Germline GPU", self)
        self.tab_chipseq_gpu = PipelineTab("ChIP-seq GPU", self)
        
        self.tabs.addTab(self.tab_germline_cpu, "Germline CPU")
        self.tabs.addTab(self.tab_germline_gpu, "Germline GPU")
        self.tabs.addTab(self.tab_chipseq_gpu, "ChIP-seq GPU")
        main_layout.addWidget(self.tabs)

        console_group = QGroupBox("Console Output")
        c_layout = QVBoxLayout()
        self.console = QTextEdit()
        self.console.setReadOnly(True)
        self.console.setFont(QFont("Consolas", 10))
        c_layout.addWidget(self.console)
        console_group.setLayout(c_layout)
        main_layout.addWidget(console_group, stretch=1)

    def browse_out(self):
        folder = QFileDialog.getExistingDirectory(self, "Select Output Directory")
        if folder: self.input_out_dir.setText(os.path.normpath(folder))

    def show_monitor(self):
        monitor = ResourceMonitor(self)
        monitor.exec()

    def to_linux_path(self, path_str):
        path = path_str.replace('\\', '/')
        if len(path) > 1 and path[1] == ':':
            drive = path[0].lower()
            path = f"/mnt/{drive}{path[2:]}"
        return path

    def append_console(self, text):
        self.console.moveCursor(QTextCursor.End)
        self.console.insertPlainText(text)
        self.console.moveCursor(QTextCursor.End)

    def start_process(self, command, run_btn, stop_btn, build_btn=None, env_dict=None):
        if self.process and self.process.state() == QProcess.Running:
            QMessageBox.warning(self, "Warning", "A process is already running!")
            return

        self.console.clear()
        self.append_console(f"Running command: {' '.join(command)}\n")
        self.append_console("-" * 60 + "\n")

        self.active_run_btn = run_btn
        self.active_stop_btn = stop_btn
        self.active_build_btn = build_btn

        self.process = QProcess()
        env = QProcessEnvironment.systemEnvironment()
        if env_dict:
            for k, v in env_dict.items():
                env.insert(k, v)
        self.process.setProcessEnvironment(env)
        
        self.process.readyReadStandardOutput.connect(self.handle_stdout)
        self.process.readyReadStandardError.connect(self.handle_stderr)
        self.process.finished.connect(self.process_finished)

        run_btn.setEnabled(False)
        if build_btn: build_btn.setEnabled(False)
        stop_btn.setEnabled(True)

        self.process.start(command[0], command[1:])

    def handle_stdout(self):
        data = self.process.readAllStandardOutput()
        self.append_console(bytes(data).decode("utf-8", errors="replace"))

    def handle_stderr(self):
        data = self.process.readAllStandardError()
        self.append_console(bytes(data).decode("utf-8", errors="replace"))

    def process_finished(self, exit_code, exit_status):
        self.append_console("-" * 60 + "\n")
        self.append_console(f"Process finished with exit code {exit_code}\n")
        if self.active_run_btn: self.active_run_btn.setEnabled(True)
        if self.active_stop_btn: self.active_stop_btn.setEnabled(False)

    def stop_process(self):
        if self.process and self.process.state() == QProcess.Running:
            self.append_console("\nStopping process...\n")
            self.process.kill()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    app.setStyleSheet(MODERN_QSS)
    window = NextflowGUI()
    window.show()
    sys.exit(app.exec())
