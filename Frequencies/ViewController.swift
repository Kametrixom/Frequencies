//
//  ViewController.swift
//  Frequencies
//
//  Created by Kametrixom Tikara on 19.05.15.
//  Copyright (c) 2015 Kametrixom Tikara. All rights reserved.
//

import Cocoa
import AVFoundation
import Accelerate

class ViewController: NSViewController, AVCaptureAudioDataOutputSampleBufferDelegate {
	@IBOutlet var freqView: FreqView!

	var session = AVCaptureSession()

	let audioSettings : [NSObject : NSNumber] = [
		AVFormatIDKey : NSNumber(unsignedInt: kAudioFormatLinearPCM),
		AVSampleRateKey : 44100.0,
		AVNumberOfChannelsKey : 1,
		AVLinearPCMBitDepthKey : 32,
		AVLinearPCMIsFloatKey : true]

	var window : [Float] = {
		// creates a hamming window
		var window = Array<Float>(count: 512, repeatedValue: 0.0)
		vDSP_hamm_window(&window, vDSP_Length(window.count), 0)
		return window
	}()

	// creates an fftSetup (can be reused for every time new samples arrive)
	var fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))

	override func viewDidLoad() {
		super.viewDidLoad()

		// Set the session input to the default audio input
		let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
		let input: AVCaptureDeviceInput!
		do {
			input = try AVCaptureDeviceInput(device: device)
		} catch {
			input = nil
		}
		session.addInput(input)
        
        
        
		// Set output to a data output, with self as delegate (every time a certain number of audio samples are captures, the function captureOutput(captureOutput:, blablabla gets called
		let output = AVCaptureAudioDataOutput()
		output.setSampleBufferDelegate(self, queue: dispatch_queue_create("Audio Buffer", DISPATCH_QUEUE_SERIAL))
        
		output.audioSettings = audioSettings
		session.addOutput(output)

		// Start the session
		session.startRunning()
	}

	func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
		print(CMSampleBufferGetNumSamples(sampleBuffer))
		// Here are some really complicated things I don't fully understand yet and it has to be handled with Pointers. This way right here works though
		var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil))
		var blockBuffer: CMBlockBuffer?

		CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, nil, &audioBufferList, sizeof(audioBufferList.dynamicType), nil, nil, UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), &blockBuffer)


		let audioBuffers = UnsafeBufferPointer<AudioBuffer>(start: &audioBufferList.mBuffers, count: Int(audioBufferList.mNumberBuffers))
		for audioBuffer in audioBuffers {
			// This value lets you finally access the samples, you can print them with something like println(Array(samples))
			let samples = UnsafeMutableBufferPointer<Float>(start: UnsafeMutablePointer<Float>(audioBuffer.mData), count: Int(audioBuffer.mDataByteSize) / sizeof(Float))

			// Apply a windowing function for better frequency accuracy (Google windowing function for more info)
			window.withUnsafeBufferPointer { (wP : UnsafeBufferPointer<Float>) -> Void in
				vDSP_vmul(wP.baseAddress, 1, samples.baseAddress, 1, samples.baseAddress, 1, 512)
			}

			// Some stuff necessary for Accelerate to calculate the fast fourier transform (FFT)
			var real = Array<Float>(count: 256, repeatedValue: 0.0)
			var imag = Array<Float>(count: 256, repeatedValue: 0.0)
			var dspSplitComplex = DSPSplitComplex(realp: &real, imagp: &imag)
			let XAsComplex = UnsafePointer<DSPComplex>(samples.baseAddress)

			vDSP_ctoz(XAsComplex, 2, &dspSplitComplex, 1, 256)
			vDSP_fft_zrip(fftSetup, &dspSplitComplex, 1, 9, FFTDirection(kFFTDirection_Forward)) // This line right here calculates the fft

			var result = Array<Float>(count: 256, repeatedValue: 0)

			vDSP_zvabs(&dspSplitComplex, 1, &result, 1, 256) // Get the magnitudes from the FFT, because only this is interesting for us

            var div : Float = 100.0
            vDSP_vsdiv(result, 1, &div, &result, 1, 256)
            
			// Set the frequencies to the newly calculated values
			freqView.freqs = result
		}
	}
}


// This class just draws the freqs variable
class FreqView : NSView {

	var freqs : [Float]? {
		didSet {
			dispatch_async(dispatch_get_main_queue()) {
				self.needsDisplay = true
			}
		}
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
	}

	override func drawRect(dirtyRect: NSRect) {
		super.drawRect(dirtyRect)

		if let freqs = freqs {
			NSColor.blackColor().setFill()

			for (index, freq) in freqs.enumerate() {
				let rect = NSRect(x: ceil(frame.width / CGFloat(freqs.count) * CGFloat(index)), y: 0, width: ceil(frame.width / CGFloat(freqs.count)), height: frame.height * CGFloat(freq))
				NSRectFill(rect)
			}
		}
	}
}






