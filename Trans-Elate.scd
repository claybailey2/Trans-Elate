//HELLO! This project is a program that morphs words in English, which is a "Stress Accent Language", into Japanese, which is a "Pitch Accent Language." The main things that this program does are:

//1) stretch an english word to be as long as its corresponding japanese word, in terms of both length and syllables
//2) shift the pitch of the soundfile being played so that it matches the pitch accent pattern of the japanese word
//3) cross-fade between the english and japanese words gradually.

// japanese words are assembled in the program from their rudimentary sounds.

//as it is set up now, it will change "nice girl" into "yasashii onnna no ko"

//give it a try!
(
s.boot;
s.reboot;
s.waitForBoot {
	//******* DEFINE CONSTANTS *******
	//hi/lo pitch ratio
	~pr = 1.25;//try increasing this

	//mora (jp syllable) length
	~ml = 0.2;
	//program does not support changing this right now;
	//I could imagine supporting time stretching for each of the japanese phonium
	//but right now we are limited by the fact that those files are all 200ms long

	//iterations required to change fully from english to Japanese
	~n = 10;//try changing


	//********** WORD BANK (USER INPUT) **********
	//try commenting/uncommenting, being careful to have all the data match up

	//number of words
	~words = 2;//dont forget to check this

	//buffers of words in order
	~bufs = [
		Buffer.read(s,("audio/words/nice.wav").resolveRelative),
		//Buffer.read(s,("audio/words/beautiful.wav").resolveRelative),
		//Buffer.read(s,("audio/words/view.wav").resolveRelative),
		Buffer.read(s,("audio/words/girl.wav").resolveRelative),

		//uncomment below to try with a whole sentence! change ~words to 1
		//Buffer.read(s,("audio/words/john_met_a_nice_girl.wav").resolveRelative),
	];

	s.sync;

	//japanese accent profiles in order
	//0 or 1 (meaning low or high)
	~accents = [
		[0, 1, 1, 0],//nice
		//[1, 0, 0, 0],//beautiful
		//[1, 0, 0],//view
		[0, 1, 1, 0, 0],//girl

		//sentence
		/*
		[
			1, 0, 0,
			0, 1, 1, 0,
			0, 1, 1, 0, 0, 1,
			0, 1, 0, 0
		]
		*/
	];

	//japanese words in order
	~kotoba = [
		[\ya, \sa, \shi, \i],//nice
		//[\ki, \re, \e, \na],//beautiful
		//[\ke, \shi, \ki],//view
		[\o, \n, \na, \no, \ko],//girl

		//sentence
		/*
		[
			\jo, \n, \wa,
			\ya, \sa, \shi, \i,
			\o, \n, \na, \no, \ko, \ni,
			\de, \a, \x, \ta
		]
		*/
	];


	//********* PRE PROCESSING  *********
	//load in japanese sounds
	~phonia = [
		\a, \i, \u, \e, \o,
		\ka, \ki, \ku, \ke, \ko,
		\sa, \shi, \su, \se, \so,
		\ta, \chi, \tsu, \te, \to,
		\na, \ni, \nu, \ne, \no,
		\ha, \hi, \hu, \he, \ho,
		\ma, \mi, \mu, \me, \mo,
		\ya, \yu, \yo,
		\ra, \ri, \ru, \re, \ro,
		\wa, \n,
		\ga, \gi, \gu, \ge, \go,
		\za, \ji, \zu, \ze, \zo,
		\da, \de, \do,
		\ba, \bi, \bu, \be, \bo,
		\pa, \pi, \pu, \pe, \po,
		\kya, \kyu, \kyo,
		\sha, \shu, \sho,
		\cha, \chu, \cho,
		\nya, \nyu, \nyo,
		\hya, \hyu, \hyo,
		\mya, \myu, \myo,
		\rya, \ryu, \ryo,
		\gya, \gyu, \gyo,
		\ja, \ju, \jo,
		\bya, \byu, \byo,
		\pya, \pyu, \pyo,
		\x//small tsu
	];
	~phBuf = ~phonia.collect{|val| Buffer.read(s,("audio/japanese/"++val++".wav").resolveRelative, numFrames: 44100 * ~ml) };
	//the .wav files are 200ms so to implement a different speed for japanese speech,
	//we would have to time-stretch down the line.

	//create array of buffers for user-input japanese words
	~kBuf = Array.fill(~kotoba.size, {|i|
		Array.fill(~kotoba[i].size, {|j|
			~phBuf[~phonia.indexOf(~kotoba[i][j])]
		})
	});

	//string together japanese-phonium buffers to construct japanese word
	//allocate all the buffers
	~stringBufs = Array.fill(~words, {|i|
		Buffer.alloc(s, 44100 * ~ml * ~kBuf[i].size, 2);
	});

	s.sync;

	//copy phonia into word constructor
	~kBuf.do({|bufs, i|
		bufs.do({|buf, j|
			buf.copyData(~stringBufs[i], 44100 * ~ml * j, 0, 44100 * ~ml)
		})
	});

	s.sync;

	//calculate essential data for running the playback synth
	~preprocess = {|buf, accent|
		var fromDur = buf.numFrames / buf.sampleRate;//original length
		var numMora = accent.size;//target num syllables
		var toDur = numMora * ~ml;//length of word in japanese
		var allDurs = Array.fill(~n, {|i|
			//array of durations changing from eng to jap in n steps
			((toDur - fromDur) / (~n - 1)) * i + fromDur
		});
		//a SinOsc will be used to interrupt the english sound into jap syllables by force
		var breakFreq = Array.fill(~n, {|i|
			//frequencies so that the sinosc maintains numMora cycles per duration
			numMora / allDurs[i]
		});
		var breakAmp = Array.fill(~n, {|i|
			//amplitude of the interrupting LFO gradually increasing from 0 to 1
			-1 * ((i / (~n - 1)) - 1).squared + 1
		});
		//return the data
		Array.newFrom([allDurs, breakFreq, breakAmp]);
	};

	//execute the function and store the results
	~preData = Array.new;
	~bufs.do{|buf, i|
		~preData = ~preData.add(~preprocess.(buf, ~accents[i]))
	};

	//ledgend
	//~preData[wordNum][listNum][iterationNum]
	//listnum: 0 = dur, 1 = freq, 2 = amp

	//calculate gradually increasing pitch multiplier based target multiplier and num iterations
	~pitchMul = Array.geom(~n, 1, ~pr.pow(1 / (~n-1)));


	//********** SYNTH DEF **********
	//the program will define a synth for each word input by the user
	//these SynthDefs will contain the pitch accents of the japanese words

	//make synthDef names
	~synthNames = Array.fill(~accents.size, {|i| ("syllablesWarp" ++ i.asString).asSymbol});

	//add a synthDef for each word
	//args: accent the accent pattern of the japanese word,
	//      string the buffer containing the japanese word constructed from its phonia
	//      i the index of the word in the user's input
	~makeDef = { |accent, string, i|
		//args: out the output bus
		//      bufnum the buffer containing the english word
		//      dur the duration of the word
		//      freq the frequency of the LFO which is splitting up the english word
		//      vol the current amplitude of the LFO
		//      hi the pitch multiplier by which the sounds will be pitch shifted up on a high accent
		SynthDef(~synthNames[i], {|out = 0, bufnum, dur, freq, vol, hi|
			var pointer, pitch, warp, jap, subvol, pan, cross, add, inter;

			//used to move through Warp1
			pointer = Line.ar(
				dur: dur,
				doneAction: Done.freeSelf
			);

			//an envelope which follows the accent pattern of the jap word
			pitch = EnvGen.kr(Env(
				Array.fill(accent.size + 1, {|i|
					if(i == 0,
						{accent[0]},
						{if (accent[i - 1] == 0,
							{1},//low pitch ratio,
							{hi}//high pitch ratio
				)})}),
				Array.fill(accent.size, {dur / accent.size}),//split into even chunks of time
				\step//no curve btw pitches; implementing smooth curves could be a way to improve
			));

			warp = Warp1.ar(
				bufnum: bufnum,
				pointer: pointer,		//has a time-stretching effect
				freqScale: pitch,		//freqScale pitch-shifts with the accent pattern
				overlaps: 6,    //pertains to the granular synthesis; season to taste
				interp: 2
			);

			//calcualate the constant to add so that the peaks stay at 1
			add = 1 - (vol / 2);
			//insert gaps in the buffer to differentiate the jap syllables
			inter = SinOsc.kr(freq, 0.25, vol / 2, add);

			jap = Warp1.ar(
				bufnum: string, //the constructed japanese word passed into ~makeDef()
				pointer: pointer,
				freqScale: pitch,
				overlaps: 6,
				interp: 2
			);

			//crossfade from en to jp
			subvol = vol.squared;//sounds sneakier this way
			pan = (subvol * 2) - 1; //the
			cross = XFade2.ar(warp * inter, jap, pan);//only need to split up the en word with inter
			Out.ar(out, Pan2.ar(cross));
			//Out.ar(out, Pan2.ar(warp*inter));//hear only en
			//Out.ar(out, Pan2.ar(cross));//hear only jap
		}).add;
	};

	//execute ~makeDef for each word
	~accents.do({|accent, i|
		~makeDef.(accent, ~stringBufs[i], i);
	});

	s.sync;


	// ********** PLAYBACK **********

	/*
	for each iteration i in ~n
	    for each word
	         play each word as it should be at iteration i
	*/

	~playback =

	Pseq(
		Array.fill(~n, {|gen| //gen is for "generation"
			Pseq(
				Array.fill(~words, {|word|
					Pbind(
						\instrument, ~synthNames[word],
						\out, 0,
						\bufnum, ~bufs[word],
						\dur, Pseq([~preData[word][0][gen]], 1),
						\freq, ~preData[word][1][gen],
						\vol, ~preData[word][2][gen],
						\hi, ~pitchMul[gen]
					)
				})
			)
		})
	, 1);

	~playback.play;

}
)